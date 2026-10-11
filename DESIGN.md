# Shatibiyyah app — design for the next version

**Design only; nothing here is implemented.** Date: 2026-09-28.

Companion files:
- `features.json`: what the app does today (40 features).
- `ROADMAP.md`: the full list of improvements.
- `~/Documents/Projects/docs/DATABASE_ARCHITECTURE_V2.md`: the data contract this builds on. It is referred to below as **V2 §n**.

**Decisions this design follows** (2026-09-28):

| decision | value |
|---|---|
| audio | **Both recordings are downloaded inside the app on demand.** No recording is bundled; the one audio file in the app is the opening verse (`assets/opening/verse-1124.mp3`, 212 KB, workspace ADR 0027) |
| feature focus | commentary reader · verse text + text mode · reciter switch · memorization tools |
| app location | stays in `~/Documents/Projects/temp/flutter_shatibiyyah` |

---

## 1. Facts the design rests on (measured today)

| | محمد بن عتيق (`muhammad-atiq-1`) | عبدالحميد القريو (`abdulhamid-alqaryu-1`) |
|---|---|---|
| file | 144,592,605 B · 2:30:37 | 252,351,225 B · 2:53:47 |
| encoding | **CBR** 128 kb/s mono (LAME "Info" header) | **VBR** ~194 kb/s stereo (Xing header) |
| cues | 1173 verses + 77 spoken titles, all `reviewed`, `same_file` timebase | same |
| notes | default recording; سورة هود restored | a 4:21 editor's introduction (0:34–4:55) comes before verse 1 |

| content | count |
|---|---|
| verses, all with a first/second hemistich split | 1173 |
| canonical chapters | 78 |
| commentary blocks: الوافي / إبراز / سراج | 766 / 1171 / 918 |
| commentary text: الوافي / إبراز / سراج (characters) | 0.59 M / 1.37 M / 0.63 M |
| links from blocks to verses | 3519 `explains`, 10 `quotes`, 4 `references` |
| segments (2605 have no heading; the rest have one: المعنى 292, preamble 83, اللغة 82, …) | 3781 |
| footnotes: anchored by stream offset / unanchored | 1827 / 3 |
| blocks marked `needs_review` / `auto_high_confidence` | 6 / 117 |
| witness spellings (3 books × 1173 verses) | 3519 |
| provenance rows linking blocks to source pages (URL + printed page) | 4134 |

**What follows from these facts:**

1. **Seeking in Al-Qaryu's VBR file is not exact.** The Xing table has 100 entries over 10,427 s, so a player seeking by it can land seconds away from the cue. Atiq's CBR file seeks exactly. See D1.
2. **There are no timings for the boundary between the two halves of a verse.** Memorization prompts that play only the first half cannot be exact yet (§7.4). Text prompts work today.
3. **Footnote markers are located by stream offsets.** The snapshot must store each marker's position inside its segment's `display_text`, counted in UTF-16 units so Dart can use it (§3.2).

---

## 2. Architecture

### 2.1 Layers

```text
┌──────────────────────────────── UI (screens, sheets, widgets) ────────────────────────────────┐
│ Reader (scan | text) · VerseTextPanel · CommentarySheet · Search · Memorize · Library · Settings│
└───────────────┬────────────────────────────────────────────────────────────────┬──────────────┘
                │ ChangeNotifier controllers (as today) + one AppScope for DI     │
┌───────────────▼──────────────┐ ┌──────────────────────────┐ ┌──────────────────▼─────────────┐
│ ReaderController             │ │ PlaybackController        │ │ StudyController                 │
│ (active verse, detach,       │ │ (engine façade, sleep     │ │ (bookmarks, notes, SRS queue,   │
│  view mode, selection)       │ │  timer, lock screen)      │ │  stats)                          │
└───────────────┬──────────────┘ └──────────┬───────────────┘ └──────────────────┬─────────────┘
┌───────────────▼─────────────────────────────▼─────────────────────────────────────▼───────────┐
│ Domain (pure Dart, unit-tested): PlaybackPlan · WindowCalculator · Normalizer ·               │
│   SearchService · Scheduler (SRS) · LegacyPrefsMigrator                                       │
└───────────────┬─────────────────────────────┬─────────────────────────────────────┬───────────┘
┌───────────────▼──────────────┐ ┌────────────▼─────────────┐ ┌─────────────────────▼──────────┐
│ content.sqlite (read-only)   │ │ DownloadManager + files   │ │ user.sqlite (read-write) + prefs │
│ Matn/Layout/Commentary/      │ │ app-support/audio/*.mp3   │ │ bookmarks, notes, memorization,  │
│ Recording repositories       │ │ sha256-verified           │ │ stats; settings stay in prefs    │
└──────────────────────────────┘ └──────────────────────────┘ └──────────────────────────────────┘
```

- **State management:** keep plain `ChangeNotifier`, as today. Add one `AppScope` (an InheritedWidget) that hands out repositories and controllers. Remove `flutter_riverpod`. The existing code is consistent without it, and the new screens don't need it.
- **Rebuild scope:** each controller notifies only its own listeners. High-rate values (position, the active verse) are separate `ValueListenable`s, so a verse change never rebuilds the whole screen (AUD-22).
- **Sources of truth:** the app reads only `content.sqlite` plus the audio files it has downloaded. `verses.json`, `chapters.json`, `timestamps.json`, `shatibiyyah.txt`, `xing-toc.json`, the Dart text parser and `kDefaultDuration` are all retired (V2 §2).

### 2.2 The playback engine, split in two

The current `AudioEngine` mixes rules with player I/O. It is split into two parts.

**`PlaybackPlan`** is pure and deterministic. It is tested with a fake clock.
- Its inputs:
  - the recording's cues and announcements
  - the mode (chapter, range or full)
  - the repeat settings
  - the pause setting
  - the pre-roll
  - whether spoken titles are played
- Its output is the next instruction: `playFrom(ms)`, `pauseFor(ms)`, `stopAt(ms)`, `announce(verse)` or `end`.
- It owns all the logic for:
  - verse repeat
  - section repeat
  - the gap between verses
  - skipping titles
  - the memorization "recite gap"

**`PlaybackEngine`** is thin and does I/O only.
- It drives `just_audio`.
- Every seek or play is stamped with a **generation token**. Async continuations from an older generation are dropped, which fixes the stale jump-back after quick next/next (AUD-20).
- Seeks are awaited.
- Stream subscriptions are cancelled when the recording changes.
- The 450 ms seek check is kept, but it can be cancelled and it checks the token.

**Window rule** (V2 §3.5), plus the pre-roll:

```text
cue(v)        start of verse v in the recording (ms)
ann(c)        non-disputed spoken title of chapter c (ms), if any
pre           fixed pre-roll for every reciter (alignment decision D2; default 250 ms)

start(v)      = max(end(v-1) if v-1 is in the same continuous play, cue(v) - pre)
end(v)        = ann(chapter starting at v+1)  if it exists and cue(v) < ann < cue(v+1)
              = cue(v+1)                      otherwise
              = duration                      for the last verse
chapter c     starts at ann(c) if titles are on and ann(c) ≤ cue(first verse), else start(first verse)
              ends at end(last verse of c)
```

- **Titles off** (a new setting, on by default): when playback crosses a chapter boundary in range or full mode, the plan jumps from `end(v)` straight to `start(v+1)`, skipping the spoken title.
- **Full mode** starts at verse 1. This skips Al-Qaryu's 4:55 introduction. The introduction can be reached from the recording's info screen (§6.3).

### 2.3 Data files at runtime

| file | where | writer | contents |
|---|---|---|---|
| `content.sqlite` | copied from `assets/content/` to app support on first run, or when the bundled `snapshot_info.source_content_sha256` changes | the build pipeline only | V2 §6.5 plus the additions in §3 |
| `audio/<slug>.mp3` | app support directory. Not the cache directory, so the OS never purges it | DownloadManager | the delivery files |
| `user.sqlite` | app support directory | the app | bookmarks, notes, memorization, stats (§3.4) |
| SharedPreferences | — | the app | settings and simple state, with v2 keys holding stable IDs (§3.5) |

---

## 3. Data design

### 3.1 Snapshot (`content.sqlite`): the V2 §6.5 tables, used as designed

Tables: `chapters` (with `short_label`), `matn_verses`, `verse_regions`, `chapter_header_regions`, `commentaries`, `commentary_blocks`, `commentary_block_verses`, `commentary_segments`, `footnotes`, `block_sources`, `reciters`, `recordings`, `verse_timings`, `chapter_announcements`.

On the data side these still need the V2 migrations for layout and labels (`verse_regions`, `chapter_header_regions`, `short_label`, the النور merge) and for book defaults, plus the `spd app-snapshot` builder. None of these exist yet (V2 Phases 18, 19 and 22).

### 3.2 Snapshot additions this design needs

| addition | shape | why | source |
|---|---|---|---|
| **footnote anchors** | `footnotes.commentary_segment_id TEXT`, `anchor_utf16 INTEGER`, `marker_number INTEGER` | Draw tappable footnote markers in the right place. The builder computes the offset from `metadata_json` global offsets minus the segment's `global_start`, mapped onto `display_text` in UTF-16 units. It asserts that the text at the offset equals the marker | `footnotes`, `commentary_segments` |
| **witness spellings** | `matn_verse_variants (matn_verse_id, commentary_id, first_hemistich, second_hemistich, similarity)` | "اختلاف النسخ" view (§5.6) | `matn_verse_variants`, with `witness` mapped to a commentary |
| **book metadata** | `commentaries`: `author_full`, `death_year_h`, `edition_note`, `source_name`, `source_url`, `license_note` | Attribution screen and the source line | `commentaries`, `editions`, `source_documents` |
| **block navigation** | none: `commentary_blocks.source_order` already exists | Previous/next explanation | — |
| **chapter parts** | `chapters.part TEXT` (`intro`, `usul`, `farsh`, `closing`), set from an input file | Chapter-list section headers (مقدمة / الأصول / فرش الحروف / الخاتمة) | new small input `inputs/app/chapter-parts.json` |
| **downloads** | `recording_files (recording_id PK, delivery_sha256, delivery_bytes, duration_ms, urls_json, content_type)` | Download and verify the audio (§6) | `config/recordings/<slug>.yaml`, new `delivery:` section |
| **hemistich cues** *(optional, later)* | `hemistich_timings (recording_id, matn_verse_id, second_start_ms, quality)` | Memorization prompts that play only the first half (§7.4) | alignment pipeline. Its DTW evidence already has word boundaries; needs review |

- **Size:** V2 measured the snapshot at 4.2 MB. Variants add about 0.4 MB and the rest is negligible, so it stays under 5 MB.
- **Where the snapshot is built:** the snapshot builder writes into the app at `temp/flutter_shatibiyyah/assets/content/`. That path is set in config, because the app stays in `temp/`.

### 3.3 Queries the new features run (all core SQL, no FTS)

| feature | query |
|---|---|
| verse text | `SELECT first_hemistich, second_hemistich, chapter_id FROM matn_verses WHERE verse_number = ?` |
| explanations for a verse, per book | V2 Q2. `explains` first, then `quotes`, ordered by `source_order` |
| which books explain a verse | V2 Q3. Returns `explained` / `outside_coverage` / `not_explained` |
| segments with footnotes | `SELECT … FROM commentary_segments WHERE commentary_block_id = ? ORDER BY order_index` plus `footnotes WHERE commentary_block_id = ? ORDER BY order_index` |
| previous/next block | `WHERE commentary_id = ? AND source_order < / > ? ORDER BY source_order DESC/ASC LIMIT 1` |
| commentary search | V2 Q7: `instr(normalized_text, ?)` over segments and footnotes. The query is normalized by the Dart normalizer, which is tested for parity with Python on all 1173 verses and a commentary sample. Results are capped per page and loaded 20 at a time |
| cues for a recording | `SELECT verse_number, start_ms FROM verse_timings JOIN matn_verses …` loaded once per recording into an `Int32List`. Announcements are loaded the same way |

### 3.4 `user.sqlite` (new)

V2 §10 put all user state in SharedPreferences. Bookmarks, notes and spaced-repetition history are collections that need queries, so they get a small writable database. Settings stay in prefs.

```sql
PRAGMA user_version = 1;
CREATE TABLE bookmarks (
  matn_verse_id TEXT PRIMARY KEY, created_at INTEGER NOT NULL, label TEXT, color INTEGER
);
CREATE TABLE notes (
  id INTEGER PRIMARY KEY, matn_verse_id TEXT NOT NULL, commentary_block_id TEXT,
  body TEXT NOT NULL, created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL
);
CREATE INDEX ix_notes_verse ON notes (matn_verse_id);
CREATE TABLE memo_state (                -- one row per verse the user started memorizing
  matn_verse_id TEXT PRIMARY KEY,
  stage TEXT NOT NULL CHECK (stage IN ('learning','review','memorized')),
  ease REAL NOT NULL DEFAULT 2.5, interval_days INTEGER NOT NULL DEFAULT 0,
  due_at INTEGER NOT NULL, reps INTEGER NOT NULL DEFAULT 0, lapses INTEGER NOT NULL DEFAULT 0,
  last_grade INTEGER, updated_at INTEGER NOT NULL
);
CREATE INDEX ix_memo_due ON memo_state (due_at);
CREATE TABLE memo_log (id INTEGER PRIMARY KEY, matn_verse_id TEXT NOT NULL, at INTEGER NOT NULL,
  grade INTEGER NOT NULL, mode TEXT NOT NULL);
CREATE TABLE listen_log (day TEXT NOT NULL, recording_id TEXT NOT NULL, verses INTEGER NOT NULL,
  seconds INTEGER NOT NULL, PRIMARY KEY (day, recording_id));
```

- Everything is keyed by stable IDs (V2 §8).
- Content updates never touch this file.
- Export and import go through a JSON backup file (settings → "نسخ احتياطي").

### 3.5 Settings keys (v2, in prefs)

| key | value |
|---|---|
| `v2.mode` | `chapter` / `range` / `full` |
| `v2.chapter` | chapter ID |
| `v2.range` | `{from, to}` verse numbers |
| `v2.recording` | recording ID |
| `v2.commentary` | commentary ID (the default book) |
| `v2.reader.view` | `scan` / `text` |
| `v2.text.scale` | 0.8–1.8 |
| `v2.titles.play` | bool |
| `v2.preroll_ms` | int |
| `v2.follow_commentary` | bool |
| `v2.session` | `{verse, recording, position_ms}` |
| `v2.chapter_progress` | map chapter ID → fraction, per recording |
| `v2.download.wifi_only` | bool |
| unchanged | `v2.*` copies of speed, pause, reps, night, brightness, boxes, keepControls |

**Migration from the legacy keys** (V2 §10):
- A frozen 79-entry map converts list index → chapter ID. Entry 52 maps to `chapter:shatibiyyah:051`, and its progress becomes `max(p51, p52)`.
- The legacy session `verseId` carries over directly.
- Legacy keys stay, dual-written, for one release.

---

## 4. Verse text and text mode

### 4.1 Verse text panel (under the scan)

```text
┌──────────────────────────── scan page ────────────────────────────┐
│                          (highlighted verse)                      │
├───────────────────────────────────────────────────────────────────┤
│ ٢٢٦  وَحَرِّكْ لِوَرْشٍ كُلَّ سَاكِنٍ آخِرٍ                              │  ← sadr
│      صَحِيحٍ بِشَكْلِ الْهَمْزِ واحْذِفْهُ مُسْهِلَا          [الشرح] [⋯] │  ← ajuz
├───────────────────────────────────────────────────────────────────┤
│ range card / mini bar (as today)                                  │
└───────────────────────────────────────────────────────────────────┘
```

**Layout and content**
- The strip sits between the page and the bottom chrome.
- It shows the verse number medallion and both halves.
- On phones the halves are stacked. The second half is indented toward the left edge, like a printed poem.
- From 600 dp up, the two halves sit side by side with a gap, the way the poem is printed.

**When it updates, and states**
- It follows the active verse.
- While detached, it shows the verse on the page being browsed, dimmed, with "البيت المُشغَّل: N".

**Actions**
- **الشرح** opens the commentary sheet (§5).
- **⋯** opens verse actions: copy, share, bookmark, note, set as range start/end, memorization status.

**Visibility**
- It can be collapsed to a single line, or hidden (a setting).
- It stays hidden in immersive mode unless "إظهار النص في الوضع الغامر" is on.

**Font**
- Scheherazade New.
- Size follows `v2.text.scale` and the system text scale.

### 4.2 Text mode reader (`v2.reader.view = text`)

**Switching**
- A toolbar toggle switches between **الصفحات** (scan) and **النص**.
- Both views share the same controllers: the active verse, detach and resume, taps, and search jumps. Only the view changes.

**Layout**
- A scrolling list of all 78 chapters.
- A chapter header is the full vocalized title plus a chapter-number badge.
- Verses are rows in poem layout (§4.1).
- The list is lazy, built as a `SliverList` with per-chapter headers.

**Playing verse**
- It has a gold background and a subtle side bar.
- The list scrolls it into the middle third of the screen only when it would leave the visible area. This is the same comfort-zone rule as the scan viewer.

**Taps**
- Tapping a verse behaves like tapping it on the scan. It seeks and switches to باب mode (sync `_onVerseTap`).
- Tapping a chapter header shows the "تشغيل الباب" band.
- Long-press opens verse actions.

**Detach and resume**
- Scrolling by hand detaches, exactly like a manual page turn.
- The existing "عودة إلى البيت N" chip re-attaches.

**Night mode and size**
- Night mode uses the dark theme colors; the scan's color filter doesn't apply.
- Font size is set with a slider in the settings sheet, and pinch-to-zoom in text mode also changes it.

**Memorization**
- In memorization mode, verse text can be masked (§7.2).

**Chapter jump**
- A chapter jump bar pinned at the top shows the current chapter name. Tapping it opens the chapter list.

---

## 5. Commentary reader (الشروح)

### 5.1 Entry points

- The **الشرح** button in the verse text panel. It opens the explanation of the active verse.
- Verse actions (long-press on the scan or in text mode) → "الشرح".
- A commentary search result (§5.5) opens the reader at the matching segment, with the match highlighted.
- The chapter-action band gets a second button, "مقدمة الباب". It opens the block that starts the chapter, and the preamble segment if there is one.
- Desktop: a third tab in the side panel, **الشرح**, beside the controls.

### 5.2 Layout (phone: a draggable sheet from 45% up to full screen; desktop: a side-panel tab)

```text
┌─────────────────────────────────────────────────────────┐
│ ─── (grip)                                              │
│ البيت ٢٣١  ·  باب نقل حركة الهمزة               [يتبع ◉] │
│ [الوافي] [إبراز المعاني] [سراج القارئ]      ← book tabs   │
│ ⓘ يشرح الأبيات ٢٣٠–٢٣٣                   ← grouped note  │
│ ─────────────────────────────────────────────────────── │
│ المعنى                                    ← heading chip│
│ أمر الناظم بتحريك كل حرف ساكن … ١ …       ← body, markers│
│ اللغة                                                    │
│ …                                                        │
│ ─────────────────────────────────────────────────────── │
│ المصدر: قرآنبيديا ص ١٠١–١٠٣ · الطبعة ص ٨٥–٨٦  [فتح ↗]    │
│ [‹ الشرح السابق]                     [الشرح التالي ›]    │
└─────────────────────────────────────────────────────────┘
```

**Book tabs**
- The default book comes first (`commentaries.is_default`), then the others in title order.
- Each tab shows the V2 Q3 state. "لا يشرح هذا البيت" is possible only for books with `sparse` coverage. All three books today are `complete`.
- The last selected book is remembered (`v2.commentary`).

**Segments**
- Each segment renders as a heading chip (its `source_heading`, or no chip for `generic`) followed by its body.
- The body is `SelectableText.rich` with justified RTL paragraphs.
- The font is Scheherazade New at 1.1× the text scale.

**Footnotes**
- Markers at `anchor_utf16` render as small raised gold digits.
- Tapping a marker opens a popover with the footnote text.
- A "الحواشي" list at the end shows all of the block's footnotes, including the 3 unanchored ones.

**Grouped blocks**
- The note "يشرح الأبيات a–b" lists every verse the block explains. Each verse is tappable and moves the reader to it.

**Cross-references**
- If the verse is cited in other blocks (`quotes`/`references`), a footer lists "ذُكر هذا البيت أيضًا في شرح البيت …".

**Trust**
- The 6 `needs_review` blocks get an amber badge: "قيد المراجعة: قد يكون موضع البيت غير دقيق".
- `auto_high_confidence` gets no badge. It is still a correct placement.

**Source line**
- Provider pages and printed pages come from `block_sources`, plus a link that opens the Quranpedia reader in the external browser (`url_launcher`).
- Siraj shows only provider pages, because it has no printed pages.

**Follow playback (يتبع)**
- When it's on, the sheet moves to the new verse's block as playback advances.
- It doesn't move while the block still covers the new verse (grouped blocks), and it doesn't move while the user is scrolling inside the sheet.
- When it's off, the reader stays on the verse the user chose.

**Previous/next**
- These move by `source_order` within the book, so a grouped block is one step.

**Reading tools**
- Font size (A− / A+).
- Copy a selection, or "نسخ الشرح" for the whole explanation, with an attribution line.
- Share.
- Bookmark the explanation, which is stored as a note with `commentary_block_id`.

### 5.3 Performance

- An explanation is queried when it is opened, never preloaded.
- The largest block (Ibraz, 26 K characters) renders as one lazily built `ListView` of segments. Paragraphs are split on `\n\n`, so no single widget holds 26 K characters.

### 5.4 Comparing books (قارن الشروح)

- **Phone:** a horizontal `PageView` with one page per book for the same verse, and a page indicator. It uses the same body renderer.
- **Tablet and desktop (≥ 840 dp):** 2 or 3 columns side by side. Columns scroll independently, and a "مزامنة التمرير" toggle is off by default.
- It is opened from the ⋯ menu in the commentary sheet.

### 5.5 Commentary search

**Where it appears**
- The unified search (desktop bar and mobile overlay) gets a third result group, **في الشروح**, after الأبواب and الأبيات.
- Filter chips: الكل · الوافي · إبراز · سراج.

**Result rows**
- Book name, the verse range the block explains, and the segment heading.
- A snippet of about 40 characters on each side of the match, highlighted with the existing `normalizeWithMap` technique.

**Behavior**
- Results are grouped by block and ordered by the first verse the block explains.
- Paging loads 20 at a time.
- The query runs in an isolate over the read-only DB; `instr()` over 2.6 M characters is a few tens of ms.
- **Normalization:** the Dart port of `normalize_matching` also folds ى/ی/ئ→ي, ة→ه, ؤ→و and ک→ك, strips punctuation and applies NFKC. It replaces today's alef-only folding in verse search too, so verse search improves as well.
- Opening a result scrolls the reader to the segment and flashes the match.

### 5.6 Spelling variants (اختلاف النسخ)

- It is in verse actions, and a link in the commentary sheet footer shows only when a book's spelling differs.
- It shows the canonical verse, then each book's spelling.
- Differing words are underlined. The comparison uses normalized word tokens, with a word-level LCS diff; no tashkeel diffs are shown.
- Each spelling shows its similarity as a percentage.

---

## 6. Reciters and downloads

### 6.1 First run (no audio yet)

**Welcome screen**
- The cover, one line about the app, and two reciter cards. Each card shows the name, total duration, download size and a sample button (§6.4).
- One card is marked "الافتراضي" (default, `is_default`).
- Buttons: **تنزيل**, and **لاحقًا** (later).

**What works without audio**
- Scans, text mode, commentary, search, bookmarks and memorization text drills all work.
- The transport shows one button, **تنزيل التلاوة**. It opens the downloads screen.

### 6.2 DownloadManager

**Transport**
- Uses the `background_downloader` package: Android WorkManager and iOS background URLSession.
- Resumes with HTTP `Range`, from the file's current size.
- It survives app restarts, and it can be paused or cancelled.

**Mirrors**
- `urls_json` lists mirrors in priority order.
- If a URL fails, it moves to the next one.

**Verification**
- After the download finishes, the file's sha256 is computed in an isolate, streaming in 1 MB chunks. This takes about 1–2 s for 250 MB.
- The hash must equal `recording_files.delivery_sha256`, and the size must equal `delivery_bytes`.
- If either doesn't match, the file is deleted and the user sees "تعذّر التحقق من الملف" with a retry button.

**Storage**
- The file is written to `…/audio/<slug>.part` and renamed to `<slug>.mp3` only after verification.
- Before starting, it checks free space: file size + 50 MB margin. If there isn't enough, it shows how much is needed.

**Settings**
- "التنزيل عبر Wi-Fi فقط" (Wi-Fi only) is on by default.
- The file lives in the app support directory, so the OS doesn't purge it.

**When the content snapshot changes**
- On a content update, if a recording's `delivery_sha256` changed, the app marks the local file "تحديث متاح" (update available).
- It keeps playing the old file until the new one is verified. The old timings still apply during that time: the snapshot keeps them until the app finishes the swap. The alternative is that the old file is blocked. Rule: the app plays only a file whose hash is in the current snapshot. If the hash isn't there, the user is asked to download again.

**States (shown on the reciter card and in settings)**

```text
none → queued → downloading(p%) → verifying → ready
             ↘ paused ↗        ↘ failed(reason) → retry
ready → update_available → downloading …
ready → deleted (user) → none
```

### 6.3 Reciter switch

**Where**
- Settings → **القارئ**, and a reciter chip in the console header.
- Recordings that haven't been downloaded show their download state instead of being selectable.

**Behavior**
- The cursor is the **verse ID** (V2 §11): the current verse is kept.
- If playback was running, it resumes in the new recording at `start(current verse)`.
- Repeat counters reset. Mode, range, speed and pause are kept.

**Per recording**
- Chapter progress and stats are kept per recording.
- The lock screen shows the new reciter.

**Recording info**
- A screen with the title, attribution, duration, encoding and a verification badge (`reviewed`, `same_file`).
- For Al-Qaryu, it has a button to play the introduction (0:34–4:55).

### 6.4 Samples before download

- A short sample of about 20 s per recording (verse 1) is **bundled**, about 300 KB each.
- This lets the user choose a reciter before downloading 145 or 252 MB.

---

## 7. Memorization tools (أدوات الحفظ)

### 7.1 Entry and scope

**Entry**
- A **حفظ** item in the app menu opens the memorization home.

**Memorization home**
- Today's review queue: the number due and a "ابدأ المراجعة" button.
- Continue learning: the next new verses.
- Per-chapter progress bars, showing memorized / learning / new.
- The daily goal and a streak.

**Scope**
- The user picks what to memorize: a chapter, a range, or "continue from the last memorized verse".

### 7.2 Masking (hiding the text)

| where | how |
|---|---|
| scan page | Paper-colored rounded rectangles are painted over `verse_regions` in the overlay painter (new layer). The mask is `#FBF7EE`, or its night-inverted color. Choices: hide all · hide all except the current verse · hide the current verse only · hide the second half. Hiding the second half is **text mode only**: the scan has no half-verse rectangles |
| text mode, verse panel | The hidden half is replaced by a blurred placeholder of the same width |
| reveal | Press and hold shows the text while held. Tap toggles. "كشف كلمة" (text mode) reveals one word per tap |

### 7.3 Study modes

| mode | how it works | uses |
|---|---|---|
| **تلقين** (listen and repeat) | Each verse plays N times (the verse repeat setting). Then comes a **silent recitation gap** lasting the verse's window duration × a factor (1.0–1.5, setting). Then the next verse. Optional: after the gap, replay the verse to check | `PlaybackPlan.reciteGap`, verse windows |
| **ربط** (chaining) | Plays verse k, then a gap in which the user recites k+1, then plays k+1 to check. Builds the links between consecutive verses | same |
| **اختبار الشطر** (half-verse quiz) | Shows the first half and hides the second. The user recites, reveals, then grades: أتقنت / ترددت / أخطأت. Text only, today | hemistich split |
| **ما بعده؟** (what comes next) | Shows verse k and hides k+1 entirely. The user recites and grades | text |
| **مراجعة** (review) | Runs the due queue. Each item uses the user's chosen check (half-verse quiz by default), and the grade updates `memo_state` | scheduler |

### 7.4 Audio-only half-verse prompts (not available yet)

- "Play only the first half" needs the time where the second half starts. That data doesn't exist.
- **Proposal:** the alignment pipeline's DTW evidence already has word boundaries. Export the start of each second half as `hemistich_timings`, spot-review about 5% of them, then ship them (§3.2).
- Until then, the half-verse quiz is text-based.

### 7.5 Scheduler

It is a small, fixed variant of SM-2, written as a pure function and unit-tested.

| grade | effect |
|---|---|
| أخطأت (0) | `interval = 0` (again today), `lapses++`, `ease = max(1.3, ease − 0.2)` |
| ترددت (1) | `interval = max(1, round(interval × 1.2))`, `ease −= 0.15` |
| أتقنت (2) | `interval = 1, 3, then round(interval × ease)`, `ease += 0.05` |

- **Stages:** `learning` until 2 correct recalls in a row; `review` after that; `memorized` once the interval reaches 21 days or more. A lapse sends a memorized verse back to `review`.
- **Daily limits:** new verses per day (default 5) and reviews per day (default 50). Both are settings.
- **Chapter progress:** a chapter counts as memorized when all its verses are memorized. The chapter list shows a second progress bar in teal, next to the listening bar.

### 7.6 Bookmarks and notes

**Bookmarks**
- Bookmarking toggles a star in verse actions.
- Bookmarked verses show a small gold star at the corner of their rectangle on the scan and next to their number in text mode.

**Notes**
- A note is free text on a verse, or on an explanation (with `commentary_block_id` set).
- A notes icon appears next to verses that have notes.

**Library screen**
- Tabs: المحفوظات (bookmarks) · الملاحظات (notes) · سجل الاستماع (listening history).
- Each list can be sorted by verse order or by date.

### 7.7 Listening stats

- The engine writes one aggregate row per day per recording to `listen_log`.
- Counted: seconds actually played, plus verses played to their end.
- **Shown:**
  - today's minutes against a goal
  - a 7-day bar chart
  - the streak
  - chapters completed for each reciter

---

## 8. Improvements to existing features (design notes)

This section keeps only the items that need design decisions. The full list is in ROADMAP Phase B.

| feature | design |
|---|---|
| lock screen | `MediaItem` is updated on each verse: title = `short_label`, artist = reciter, album = "البيت N". Skip buttons map to previous/next verse through `AudioHandler` callbacks |
| interruptions | Use the `audio_session` speech/music config: pause on call or headphone unplug, and never auto-resume after a call ends. iOS gets `UIBackgroundModes: audio` |
| repeat counters | A small chip on the medallion, "البيت ٢/٥". A 3 px ring around the medallion shows section loops. The inter-verse pause shows a countdown ring |
| settings sheet | One scrolling sheet with these sections: <br>• التلاوة: reciter, titles, pre-roll, speed <br>• العرض: view, night, brightness, boxes, text size, text in immersive mode <br>• الشرح: default book, follow <br>• الحفظ: daily limits, gap factor <br>• التنزيلات <br>• نسخ احتياطي <br>• حول (about) |
| chapter list | 78 entries grouped by `part`, with a filter box. Rows show a "now playing" dot, the listening bar and the memorization bar |
| search | Adds verse-number jump: a query that is all digits (Arabic-Indic, Persian or ASCII) shows "انتقل إلى البيت N" first. Results are paged lazily. The last 10 queries are shown when the field is empty |
| app menu | A **☰** in the toolbar opens: الحفظ · المكتبة · التنزيلات · الإعدادات · حول. The reader stays the home screen |
| sleep timer | Options: 15 / 30 / 45 / 60 min, end of the verse, end of the chapter, end of the range. Set from a timer chip on the console |

---

## 9. Acceptance criteria (the tests to write when implementing)

| area | criteria |
|---|---|
| windows | For both recordings, the Dart `WindowCalculator` equals the V2 Q4/Q6 SQL oracle for all 1173 verses and all 78 chapters, with titles on and off, and with pre-roll 0 and 250 |
| engine | Tests with a fake player cover: <br>• verse repeat N / ∞ and section repeat N / ∞ <br>• pause gap <br>• recite gap <br>• title skip across a chapter boundary <br>• next/next/next under 100 ms with no jump-back <br>• switching recordings mid-verse keeps the verse |
| seeking | On a device, seek to 50 random cues in each downloaded file. Each lands within 50 ms, measured by position after the seek settles. Al-Qaryu must pass this before it ships (see D1) |
| downloads | Test these cases: kill during download → resume; flip the network to a mirror; a corrupted byte fails verification; low disk space; Wi-Fi only |
| commentary | Every footnote whose anchor is set renders at a character equal to its marker. All 2855 blocks open. The Ibraz 26 K-character block scrolls at 60 fps on a mid-range Android phone |
| search | The Dart normalizer equals the Python one on all 1173 verses and on 500 sampled segments. For a query, the Python search over the same text returns the same verse set as the app |
| migration | Legacy prefs for all 79 indices convert correctly, and النور progress is `max(p51, p52)`. A fresh install and an upgrade are both tested |
| memorization | Scheduler unit tests. A mask covers every rectangle on every page (golden test of 3 pages) |

---

## 10. Open decisions

| # | decision | options | recommendation |
|---|---|---|---|
| **D1** | How to deliver Al-Qaryu's VBR file | (a) Deliver a **CBR re-encode**, e.g. 96 kb/s mono ≈ 125 MB or 64 kb/s mono ≈ 83 MB. Then measure its offset against the reviewed file by cross-correlation → `timebase_status = verified` (V2 already supports this). <br>(b) Keep the VBR file and turn on precise seeking: Android `FLAG_MP3_ENABLE_INDEX_SEEKING`, iOS `preferPreciseDurationAndTiming`. Seeks near the end of a 252 MB file can then be slow | **(a).** Exact seeking and half the download. Consider re-encoding Atiq too (64k mono ≈ 72 MB) and verifying it the same way |
| **D2** | Where to host the audio | Needs HTTPS with `Range` support. Options: Cloudflare R2 (no egress fees) · GitHub Releases (≤ 2 GB per file, free) · Firebase Storage | R2, or GitHub Releases for a start. Listing two mirrors is supported |
| **D3** | Pre-roll value (alignment decision D2) | 0 / 200 / 250 / 300 ms, one value for every reciter | 250 ms, adjustable in settings |
| **D4** | User data store | `user.sqlite` for collections + prefs for settings (this design) · everything in prefs (V2 §10) | `user.sqlite` |
| **D5** | Half-verse timings | Produce them from the alignment evidence and review them · text-only quizzes | Produce them later. Text-only quizzes are enough for v1 |
| **D6** | Displaying commentary text | Confirm that Quranpedia's terms (recorded in `source_documents.license_note`) allow showing the text in the app with attribution | Check before release |
| D7 | Play audio while it downloads | Stream from the URL while caching the file (`LockCachingAudioSource`, experimental) · download first | Download first. Consider streaming later, and only with CBR files |

---

## 11. Build order for when implementation starts

1. **Data side:**
   - V2 migrations for layout and books
   - the §3.2 additions
   - `spd app-snapshot` writing to `temp/flutter_shatibiyyah/assets/content/`
   - `delivery:` sections in the recording YAMLs, once D1 and D2 are decided
2. **App foundation:**
   - `AppScope` and the repositories
   - the normalizer with its parity test
   - `PlaybackPlan` and `PlaybackEngine` with the window tests
   - prefs v2 and the legacy migration
   - `user.sqlite`
3. **Downloads and reciters:** welcome screen, DownloadManager, reciter switch, lock screen, interruptions.
4. **Verse text panel, then text mode.**
5. **Commentary reader:** the sheet, footnotes, source line and follow mode. Then comparing books, commentary search and variants.
6. **Memorization:** masking, the study modes, the scheduler. Then bookmarks, notes, the library screen and stats.
7. **The rest of ROADMAP Phase B.**
