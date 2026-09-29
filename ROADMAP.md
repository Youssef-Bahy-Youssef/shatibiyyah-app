# Shatibiyyah app — improvement and new-feature roadmap

> **Decisions 2026-09-28:**
> - Both recordings are downloaded in the app on demand. Nothing is bundled.
> - Design only for now.
> - Focus: the commentary reader, verse text + text mode, the reciter switch, memorization.
> - The app stays in `temp/`, so item A1's move does not apply.
>
> The detailed design is in **`DESIGN.md`**.

Date: 2026-09-28. Inputs:
- `features.json`: the inventory of the app as it is today.
- `shatibiyyah-data`: three commentaries and two reviewed recordings.
- `docs/DATABASE_ARCHITECTURE_V2.md`: the `content.sqlite` contract.
- The audit items `AUD-nn` in `docs/ARCHITECTURE.md`.

## Where things stand

| | today's app | what the data platform already has |
|---|---|---|
| text | `shatibiyyah.txt`, parsed in Dart; used only by search | 1173 vocalized verses with a clean first/second hemistich split, plus a normalized form |
| chapters | 79 list entries; entries 51 and 52 overlap (النور); 7 ranges are stretched (AUD-19) | 78 canonical chapters |
| layout | `verses.json`, `chapters.json` | same rectangles. The V2 `verse_regions` / `chapter_header_regions` tables are **not built yet** |
| audio | one 71 MB file (`audio.mp3`, no سورة هود). Timings are unverified legacy cues | **2 recordings, fully reviewed, `same_file` timebase**: <br>• محمد بن عتيق, 145 MB, Hud restored, default <br>• عبدالحميد القريو, 252 MB <br>Each has 1173 verse cues and 77 spoken chapter titles, in integer ms |
| commentary | none | الوافي (766 blocks), إبراز المعاني (1171), سراج القارئ (918): <br>3519 verse links, 3781 segments, 1830 footnotes, 3519 witness spellings, 14 cross-references, source page and printed page for each block |
| client DB | — | `content.sqlite` is designed (V2 §6.5), but the `spd app-snapshot` builder does not exist |

**Constraint: the disk has 3.1 GB free.** MP3s must be APFS clones (`cp -c`), and Flutter build output needs cleaning between builds.

---

## Phase A — Foundation

Every item after this phase depends on it.

| # | work | fixes / enables |
|---|---|---|
| A1 | Put the app under version control at `Shatibiyyah/flutter_shatibiyyah`. That is the path the recording configs and the snapshot target already assume. First add `android/keystore.properties` to `.gitignore` (AUD-24). Exclude media, with a hash manifest. Remove the Finder duplicates, but only with your OK (AUD-25) | Safe refactors, history |
| A2 | Data side: V2 migrations for layout + labels (`verse_regions`, `chapter_header_regions`, `chapters.short_label`, the النور merge) and book defaults (`commentaries.is_default/coverage`). Then add a `spd app-snapshot` builder that checks the shipped audio hashes and the 94 page files | One source of truth. Retires 4 JSON files, `xing-toc.json`, the Dart text parser, and `kDefaultDuration` |
| A3 | Flutter data layer: `sqflite`, read-only, copied from assets on first run or when the version changes. Small repositories: `MatnRepository`, `LayoutRepository`, `CommentaryRepository`, `RecordingRepository`. A Dart port of `normalize_matching`, with a parity test over all 1173 verses | Every feature below |
| A4 | Playback engine on the V2 rules: <br>• integer-ms cues per recording <br>• verse window = next cue, cut short at a non-disputed chapter announcement <br>• a chapter starts at its announcement <br>• a generation token on every seek (AUD-20), awaited seeks, stream subscriptions disposed <br>• one fixed pre-roll for every reciter (alignment decision D2) | Correct chapter bounds (fixes the 912-only النور bug), no stale jump-backs, ready for more reciters |
| A5 | Prefs v2 keyed by stable IDs (`verse:…`, `chapter:…`, `recording:…`, `commentary:…`), with a one-time migration from legacy list indices. Progress and session are carried over | Saved state survives content changes. Fixes chapters that never reach 100% |
| A6 | Tests: <br>• engine tests against a fake player: repeats, section loop, pause, boundaries, announcements <br>• repository tests on a small fixture snapshot <br>• golden tests for the main screens | A safety net for everything else |

## Phase B — Make the existing features very good

Numbered by area from `features.json`.

**Audio**
- B1. iOS background playback: add the `UIBackgroundModes: audio` entry.
- B2. Handle interruptions with `audio_session`: pause on a phone call or when headphones are unplugged, and duck under navigation prompts.
- B3. Lock screen and notification: show the chapter name and "البيت N" and update them on every verse. Map the lock-screen skip buttons to previous/next verse.
- B4. Show repeat counters on the medallion, e.g. "٢/٥" for verse repeats and the section-loop count. Show a countdown ring during the inter-verse pause.
- B5. Chapter-title handling: a setting to play or skip the spoken chapter titles. While a title is playing, show the chapter name instead of a verse (V2 Q5).
- B6. Error UI for audio load failure, with a retry button. `onLoadError` is currently unused.
- B7. Sleep timer: stop after N minutes, or at the end of the verse, chapter, or range.

**Page viewer**
- B8. Pre-cache the next and previous pages so turning a page never flashes. Add an animated page-turn transition.
- B9. Keep the zoom level across page changes during playback. The current "cinematic turn" resets to 1.5×.
- B10. Landscape two-page spread on tablets. Optional.

**Navigation, range and search**
- B11. Chapter list: 78 canonical chapters, a "now playing" marker, a filter box, and أصول / فرش section headers.
- B12. Range picking: long-press a verse, then drag to another verse to set a نطاق directly on the page. Add a "from chapter X to chapter Y" preset.
- B13. Search:
  - Python-parity normalization, so ى/ي, ة/ه and ؤ/و also match.
  - Typing a verse number (١٢٣ or 123) jumps to that verse.
  - Lazy results with no 30-item cap.
  - Recent searches.
  - Commentary search, see C6.

**Chrome, settings and quality**
- B14. A real settings sheet: night mode, brightness, verse boxes, keep controls visible, pre-roll, reciter, default commentary, text size. It replaces the unused `settingsOpen` state.
- B15. A first-run hint for immersive mode, using the unused `immersiveHintShown` key.
- B16. Accessibility:
  - Semantics labels on every control.
  - Respect the system text-scale setting.
  - Make the page viewer usable with a screen reader.
- B17. Performance: split the root `AnimatedBuilder` so a verse change doesn't rebuild the whole screen (AUD-22).
- B18. Hygiene:
  - One app name on every platform.
  - Remove `flutter_riverpod`.
  - Make the iOS orientation list match the portrait lock.
  - Write a real README.

## Phase C — New features from the data

| # | feature | data it uses | notes |
|---|---|---|---|
| **C1** | **Verse text panel (نص البيت)**: vocalized first and second hemistich of the playing verse under the page, synced. Copy and share | `matn_verses` | The app shows no verse text today (AUD-23). This is also the base for future word highlighting |
| **C2** | **Commentary reader (الشروح)**: tap a verse, then "الشرح". Tabs for الوافي / إبراز المعاني / سراج القارئ. Segments show their headings (المعنى، اللغة، …) and footnotes appear inline | `commentary_blocks`, `_block_verses`, `_segments`, `footnotes` | Grouped blocks say "يشرح الأبيات ٢٣٠–٢٣٣". A book can follow the playing verse (auto-advance while listening) |
| C3 | **Source and trust line** under each explanation: provider page, printed page, a link to the Quranpedia reader page, and a small badge for the 6 blocks that need review | `block_sources`, `review_status` | Scholarly transparency |
| **C4** | **Choose reciter**: محمد بن عتيق or عبدالحميد القريو. Switching keeps the current verse, because the cursor is the verse ID. Adds an attribution screen | `reciters`, `recordings`, `verse_timings` | Depends on the audio-shipping decision |
| C5 | **Compare commentaries**: the same verse in 2–3 books side by side (tablet) or swipeable (phone) | same as C2 | |
| C6 | **Commentary search**: search inside the three books; results are grouped by verse and open the reader at the match | `commentary_segments.normalized_text`, `footnotes` | `instr()` search, per V2 |
| C7 | **Spelling variants (اختلاف النسخ)**: how each commentary's edition spells the verse, with differences from the canonical text highlighted | `matn_verse_variants` (3519) | Specialist value, and the data is ready |
| C8 | **Cross-references**: "هذا البيت مذكور أيضًا في شرح البيت …" | `relation_type = quotes/references` | Small, cheap |
| **C9** | **Memorization mode (وضع الحفظ)**: <br>• hide or blur the verse on the page and in the text panel; tap to reveal <br>• "listen N times, then recite in the silent gap" <br>• hear the first hemistich, recall the second <br>• mark a verse memorized, with a spaced-repetition review queue <br>• per-chapter memorization progress | hemistich split, verse windows, prefs | Uses verse windows and hemistich text together |
| C10 | **Bookmarks and notes** per verse, with a list screen | prefs v2 or a small user DB (stable IDs) | |
| C11 | **Listening stats**: daily time, verses listened, streak, and chapters completed per reciter | engine events | |
| C12 | **Text-mode reader**: scroll the vocalized poem as text, with the playing verse highlighted and adjustable font size. An alternative to the scans | `matn_verses`, `chapters` | Works well at night and on small phones |
| C13 | **Share a verse** as text or as an image card (verse + chapter + number) | `matn_verses` | |
| C14 | **Deep links** such as `shatibiyyah://verse/226?commentary=al-wafi` | stable IDs | |
| later | Word-level highlighting | needs `matn_tokens` + `word_timings` (V2 §12.2) | Blocked until word alignment exists |

## Suggested order

1. **A1 → A6.** The foundation. Some bugs disappear with it: the النور range, stretched chapter progress, stale seek jumps, and the missing سورة هود audio.
2. **Quick wins:** B1, B2, B3, B6, B14. Small, and very visible.
3. **C1 text panel, then C2 + C3 commentary reader.** The data investment finally reaches users.
4. **C4 reciter switch**, and B5 chapter titles.
5. **C9 memorization, then C10 bookmarks.**
6. **The rest of B and C**, in whatever order you prefer.
