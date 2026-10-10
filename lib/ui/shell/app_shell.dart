// lib/ui/shell/app_shell.dart — the shell (item 3.4, ADR 0019): the four tabs in
// the binding.
//
// The dock floats over the current tab's screen (v2.css .dock: 10 px from the
// sides, 28 px above the bottom edge under a 34 px home indicator): now playing
// plus the tabs on «المتن» and «الفهرس», the tabs alone on «المحفوظ» and
// «الإعدادات» (v2.js dock(st, cur, withNp)). On the reader a tap on the page
// hides it with the top bar, 150 px down and out in 320 ms (emphasized) while it
// fades in 200 ms, and a second tap brings it back; on the other tabs it always
// shows. Choosing a tab shows the reader's chrome again (index.html go()).
//
// Pushed screens (search, downloads, the commentary) cover the dock: it belongs
// to the top level only. Each tab's screen is built on its first visit and kept.
import 'package:flutter/material.dart';

import '../../services/download_manager.dart';
import '../../utils/arabic.dart';
import '../design/components/dock.dart';
import '../design/components/tz_motion.dart';
import '../design/tokens.g.dart';
import '../design/tz_theme.dart';
import '../reader/fixed_page_layout.dart';
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

  /// The dock's fade: its opacity is 0 while the reader's chrome is hidden.
  static const dockChromeKey = ValueKey('shell-dock-chrome');

  /// The shell above [context], or null for a screen shown on its own.
  static AppShellState? of(BuildContext context) => context.findAncestorStateOfType<AppShellState>();

  @override
  State<AppShell> createState() => AppShellState();
}

class AppShellState extends State<AppShell> {
  late DockTab _tab = widget.initialTab;
  final Set<DockTab> _built = {};

  DockTab get tab => _tab;

  /// Shows [t]. Navigating shows the reader's chrome again, as the prototype does.
  void select(DockTab t) {
    if (t != _tab) setState(() => _tab = t);
    widget.reader.showChrome();
  }

  /// Whether the dock carries the now-playing row on [t] (v2.js: withNp).
  static bool nowPlayingOn(DockTab t) => t == DockTab.matn || t == DockTab.contents;

  @override
  Widget build(BuildContext context) {
    final reader = widget.reader;
    _built.add(_tab);
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return AnimatedBuilder(
      animation: Listenable.merge([reader, ?reader.library]),
      builder: (context, _) {
        final onReader = _tab == DockTab.matn;
        final withRow = nowPlayingOn(_tab);
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
              // While verses are being selected, the reader's own bar takes the dock's place.
              if (!(onReader && reader.selecting))
                Positioned(
                  left: ReaderTokens.dockSide,
                  right: ReaderTokens.dockSide,
                  bottom: ReaderTokens.dockBottom(safeBottom),
                  child: _DockChrome(
                    visible: !onReader || reader.chromeVisible,
                    height: withRow ? ReaderTokens.dockHeight : ReaderTokens.dockTabsHeight,
                    // The dock is a fixed-height binding, like a system tab bar: its text
                    // follows the system size up to 1.3×, not beyond (item 3.12 revisits).
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        textScaler: MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3),
                      ),
                      child: Dock(nowPlaying: withRow ? _nowPlaying() : null, current: _tab, onTab: select),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _screen(DockTab t) => switch (t) {
        DockTab.matn => ReaderScreen(reader: widget.reader),
        DockTab.contents => IndexScreen(reader: widget.reader),
        DockTab.saved => SavedScreen(reader: widget.reader),
        DockTab.settings => SettingsScreen(reader: widget.reader),
      };

  /// The now-playing row from the reader and the library (v2.js npRow): the
  /// recited verse and its place in the section, else what the download is doing.
  /// The paused state is 3.7's; until then it reads as not downloaded, resumable.
  NowPlaying _nowPlaying() {
    final r = widget.reader;
    final rec = r.recording;
    final library = r.library;
    if (r.audioAvailable) {
      final scope = r.engine!.plan.scope;
      final of = scope.toVerse - scope.fromVerse + 1;
      final at = (r.verse - scope.fromVerse + 1).clamp(1, of);
      final repeats = r.settings.verseRepeats;
      final parts = [
        rec.reciterName,
        if (r.speed != 1) '${ar(r.speed)}×',
        if (repeats == null || repeats > 1) 'تكرار ${ar(r.verseRepetition)}/${repeats == null ? '∞' : ar(repeats)}',
      ];
      return NpPlaying(
        verse: ar(r.verse),
        position: '${ar(at)} من ${ar(of)}',
        subtitle: parts.join(' · '),
        playing: r.playing,
        progress: (at - 1 + 0.4) / of,
        onToggle: r.playPause,
        onNext: r.next,
      );
    }
    final progress = library?.progressOf(rec);
    if (library != null && library.isDownloading(rec)) {
      final f = progress?.fraction ?? 0;
      return NpDownloading(
        percent: '${ar((f * 100).floor())}٪',
        progress: f,
        subtitle: '${megabytes(progress?.received ?? 0)} من ${megabytes(rec.localBytes)} · يكمل في الخلفية',
        onPause: () => library.pause(rec),
      );
    }
    if (library != null && progress?.phase == DownloadPhase.failed) {
      final why = progress!.error == DownloadError.network ? 'انقطع الاتصال' : 'تعذّر التنزيل';
      final from = progress.received > 0 ? ' · سيُستأنف من ${ar((progress.fraction * 100).floor())}٪' : '';
      return NpFailed(subtitle: '$why$from', onRetry: () => library.download(rec));
    }
    final paused = library?.isPaused(rec) ?? false;
    return NpNone(
      subtitle: paused
          ? 'متوقف عند ${ar(((progress?.fraction ?? 0) * 100).floor())}٪ · ${megabytes(rec.localBytes)}'
          : '${rec.reciterName} · ${megabytes(rec.localBytes)} · مرة واحدة',
      onDownload: () => library?.download(rec),
    );
  }
}

/// The dock's chrome: hidden, it slides 150 px down and out (v2.css .chrome-off .dock).
class _DockChrome extends StatelessWidget {
  final bool visible;
  final double height;
  final Widget child;
  const _DockChrome({required this.visible, required this.height, required this.child});

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: !visible,
        child: ExcludeSemantics(
          excluding: !visible,
          child: AnimatedOpacity(
            key: AppShell.dockChromeKey,
            opacity: visible ? 1 : 0,
            duration: tzDuration(context, TzMotion.medium),
            curve: TzMotion.standard,
            child: AnimatedSlide(
              offset: Offset(0, visible ? 0 : 150 / height),
              duration: tzDuration(context, TzMotion.long),
              curve: TzMotion.emphasized,
              child: child,
            ),
          ),
        ),
      );
}
