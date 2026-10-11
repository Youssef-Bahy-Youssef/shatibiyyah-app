// lib/ui/shell/app_shell.dart — the shell (item 3.4, ADR 0019): the four tabs in
// the binding.
//
// The dock floats over the current tab's screen (v2.css .dock: 10 px from the
// sides, 28 px above the bottom edge under a 34 px home indicator): now playing
// plus the tabs on «المتن» and «الفهرس», the tabs alone on «المحفوظ» and
// «الإعدادات» (v2.js dock(st, cur, withNp)). It always shows, on every tab: a
// tap on the page does not hide it or the top bar (the prototype's .chrome-off
// is not built).
//
// Pushed screens (search, downloads, the commentary) cover the dock: it belongs
// to the top level only. Each tab's screen is built on its first visit and kept.
import 'package:flutter/material.dart';

import '../../services/download_manager.dart';
import '../../utils/arabic.dart';
import '../design/components/dock.dart';
import '../design/tz_theme.dart';
import '../reader/fixed_page_layout.dart';
import '../reader/player_sheet.dart';
import '../reader/reader_controller.dart';
import '../reader/reader_screen.dart';
import 'index_screen.dart';
import 'saved_screen.dart';
import 'settings_screen.dart';
import 'shell_page.dart' show ShellInset;

/// The shell at the root, for what is not under it: a tapped reminder opens the reader.
final GlobalKey<AppShellState> appShell = GlobalKey<AppShellState>();

class AppShell extends StatefulWidget {
  final ReaderController reader;
  final DockTab initialTab;
  const AppShell({super.key, required this.reader, this.initialTab = DockTab.matn});

  /// The shell above [context], or null for a screen shown on its own.
  static AppShellState? of(BuildContext context) => context.findAncestorStateOfType<AppShellState>();

  /// Opens [verse] in the reader from anywhere: a tab (the shell above it) or a
  /// pushed screen (the shell at the root), then back to the top level. A
  /// recitation that is playing goes on where it is (ReaderController.goToVerse).
  static void openVerse(BuildContext context, ReaderController reader, int verse) {
    reader.goToVerse(verse);
    (of(context) ?? appShell.currentState)?.select(DockTab.matn);
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  late DockTab _tab = widget.initialTab;
  late final Set<DockTab> _built = {_tab};

  DockTab get tab => _tab;

  /// Shows [t].
  void select(DockTab t) {
    if (t != _tab) setState(() => _built.add(_tab = t));
  }

  /// Whether the dock carries the now-playing row on [t] (v2.js: withNp).
  static bool nowPlayingOn(DockTab t) => t == DockTab.matn || t == DockTab.contents;

  @override
  Widget build(BuildContext context) {
    final reader = widget.reader;
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return AnimatedBuilder(
      animation: Listenable.merge([reader, ?reader.library]),
      builder: (context, _) {
        final onReader = _tab == DockTab.matn;
        return Scaffold(
          backgroundColor: TzTheme.of(context).colors.bg,
          body: Stack(
            fit: StackFit.expand,
            children: [
              IndexedStack(
                index: _tab.index,
                children: [
                  for (final t in DockTab.values)
                    ShellInset(
                      bottom: ReaderTokens.dockInset(safeBottom, nowPlaying: nowPlayingOn(t)),
                      child: _built.contains(t) ? _screen(t) : const SizedBox.shrink(),
                    ),
                ],
              ),
              // On the reader the dock rides inside the screen, under its popovers and
              // their scrim (v2: dock z 6, spotlight 8, popover 9); here it floats over
              // the other tabs.
              if (!onReader)
                Positioned(
                  left: ReaderTokens.dockSide,
                  right: ReaderTokens.dockSide,
                  bottom: ReaderTokens.dockBottom(safeBottom),
                  child: _dock(),
                ),
            ],
          ),
        );
      },
    );
  }

  /// The dock for the current tab.
  Widget _dock() {
    final withRow = nowPlayingOn(_tab);
    // The dock is a fixed-height binding, like a system tab bar: its text
    // follows the system size up to 1.3×, not beyond. Item 3.12 keeps this:
    // every tab keeps its icon and a 48 px target, and what it leads to scales in full.
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
      ),
      child: Dock(nowPlaying: withRow ? _nowPlaying() : null, current: _tab, onTab: select),
    );
  }

  Widget _screen(DockTab t) => switch (t) {
        DockTab.matn => ReaderScreen(reader: widget.reader, dock: _dock()),
        DockTab.contents => IndexScreen(reader: widget.reader),
        DockTab.saved => SavedScreen(reader: widget.reader),
        DockTab.settings => SettingsScreen(reader: widget.reader),
      };

  /// The now-playing row from the reader and the library (v2.js npRow): the
  /// recited verse and its place in the section (a tap opens the player), else
  /// what the download is doing: on its way, failed, paused, or not started.
  NowPlaying _nowPlaying() {
    final r = widget.reader;
    final rec = r.recording;
    final library = r.library;
    if (r.audioAvailable) {
      final section = r.section!;
      final of = section.toVerse - section.fromVerse + 1;
      final at = (r.verse - section.fromVerse + 1).clamp(1, of);
      final repeats = r.settings.verseRepeats;
      // What differs from the defaults; the row keeps these when the reciter's name does not fit.
      final settings = [
        if (r.speed != 1) '${ar(r.speed)}×',
        if (repeats == null || repeats > 1) 'تكرار ${ar(r.verseRepetition)}/${repeats == null ? '∞' : ar(repeats)}',
      ];
      return NpPlaying(
        verse: ar(r.verse),
        position: '${ar(at)} من ${ar(of)}',
        subtitle: [rec.reciterName, ...settings].join(' · '),
        compactSubtitle: settings.isEmpty ? null : settings.join(' · '),
        playing: r.playing,
        progress: (at - 1 + 0.4) / of,
        onPrevious: r.previous,
        onToggle: r.playPause,
        onNext: r.next,
        onOpen: () => showPlayerSheet(context, r),
      );
    }
    final progress = library?.progressOf(rec);
    if (library != null && library.isDownloading(rec)) {
      final f = progress?.fraction ?? 0;
      return NpDownloading(
        percent: '${ar((f * 100).floor())}٪',
        progress: f,
        // What it waits for, if it waits; else how far it is.
        subtitle: switch (progress?.phase) {
          DownloadPhase.waitingForNetwork => 'بانتظار الاتصال بالشبكة · يُستأنف تلقائيًا',
          DownloadPhase.waitingForWifi => 'بانتظار شبكة Wi-Fi',
          DownloadPhase.verifying => 'يُتحقَّق من الملف…',
          _ => '${ar(((progress?.received ?? 0) / 1e6).round())} من ${megabytes(rec.localBytes)} · يكمل في الخلفية',
        },
        onPause: () => library.pause(rec),
      );
    }
    if (library != null && progress?.phase == DownloadPhase.failed) {
      // The reason, worded as «التنزيلات» words it.
      final why = switch (progress!.error) {
        DownloadError.noUrls => 'التنزيل غير متاح بعد',
        DownloadError.noSpace => 'المساحة غير كافية',
        DownloadError.verification => 'تعذّر التحقق من الملف',
        _ => 'انقطع الاتصال',
      };
      final resumes = progress.error == DownloadError.network && progress.received > 0;
      return NpFailed(
        subtitle: resumes ? '$why · سيُستأنف من ${ar((progress.fraction * 100).floor())}٪' : why,
        onRetry: () => library.download(rec),
      );
    }
    if (library != null && library.isPaused(rec)) {
      return NpNone(
        subtitle: 'متوقف عند ${ar(((progress?.fraction ?? 0) * 100).floor())}٪ · ${megabytes(rec.localBytes)}',
        action: 'متابعة',
        onDownload: () => library.download(rec),
      );
    }
    if (library != null && library.needsUpdate(rec)) {
      // An app update brought a new recording: the old file is not played.
      return NpNone(
        subtitle: 'يلزم تحديث التلاوة · ${megabytes(rec.localBytes)}',
        onDownload: () => library.download(rec),
      );
    }
    return NpNone(
      subtitle: '${rec.reciterName} · ${megabytes(rec.localBytes)} · مرة واحدة',
      onDownload: () => library?.download(rec),
    );
  }
}
