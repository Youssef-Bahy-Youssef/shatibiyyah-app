// lib/ui/design/components/dock.dart — the binding (item 3.3, ADR 0019; v2.js
// dock() and npRow(), v2.css .dock, .np-row, .tabsrow).
//
// One floating lapis object: the now-playing row (62 px) in one of four states
// over the four tabs (54 px). The active tab is filled, in onCover, with a gilt
// lozenge under it. The row's 44 px buttons have 48 px targets; their gaps are
// 4 px smaller, so they are drawn exactly where the prototype puts them. While
// a recitation is loaded the row ends in the player's transport, in the player's
// order: previous verse, play, next verse, 4 px apart (v2.css .np-ctl), so
// their targets touch.
import 'dart:async';

import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_icon.dart';
import '../tz_theme.dart';
import 'khatam.dart';
import 'ornament.dart';
import 'tz_motion.dart';

enum DockTab {
  matn('المتن', 'book', 'book-f'),
  contents('الفهرس', 'list', 'list-f'),
  saved('المحفوظ', 'bookmark', 'bookmark'),
  settings('الإعدادات', 'gear', 'gear-f');

  final String label, icon, activeIcon;
  const DockTab(this.label, this.icon, this.activeIcon);
}

/// What the now-playing row shows.
sealed class NowPlaying {
  const NowPlaying();
}

/// A recitation is loaded: the verse, its place in the section, the reciter and settings.
class NpPlaying extends NowPlaying {
  final String verse; // «٢٢٩»
  final String position; // «٤ من ٩»
  final String subtitle; // «محمد بن عتيق · ١٫٢٥× · تكرار ٢/٣»

  /// The line without the reciter's name («١٫٢٥× · تكرار ٢/٣»), shown when the
  /// whole of [subtitle] does not fit beside the buttons. Null when the name is all there is.
  final String? compactSubtitle;
  final bool playing;

  /// Through the section as time, 0…1: nothing at its start, 1 at its end.
  final double progress;

  /// [progress] as the recitation moves on, between two builds of the row.
  final Stream<double>? progressChanges;
  final VoidCallback onPrevious, onToggle, onNext;

  /// A tap on the row itself (the khatam and the text): the player.
  final VoidCallback? onOpen;
  const NpPlaying(
      {required this.verse,
      required this.position,
      required this.subtitle,
      this.compactSubtitle,
      required this.playing,
      required this.progress,
      this.progressChanges,
      required this.onPrevious,
      required this.onToggle,
      required this.onNext,
      this.onOpen});
}

/// No recitation on the device yet: «تنزيل», or «متابعة» for one that was paused.
class NpNone extends NowPlaying {
  final String subtitle;
  final String action;
  final VoidCallback onDownload;
  const NpNone({required this.subtitle, this.action = 'تنزيل', required this.onDownload});
}

class NpDownloading extends NowPlaying {
  final String percent; // «٤٢٪»
  final double progress;
  final String subtitle;
  final VoidCallback onPause;
  const NpDownloading({required this.percent, required this.progress, required this.subtitle, required this.onPause});
}

class NpFailed extends NowPlaying {
  final String subtitle;
  final VoidCallback onRetry;
  const NpFailed({required this.subtitle, required this.onRetry});
}

class Dock extends StatelessWidget {
  final NowPlaying? nowPlaying;
  final DockTab current;
  final ValueChanged<DockTab> onTab;

  /// Where the selection stands as a tab's index, gliding from one tab to the
  /// next (ADR 0037): the lozenge slides and the two tabs trade their ink. Without
  /// it, [current] alone.
  final Animation<double>? selection;

  /// How much of the now-playing row shows, 0…1, as it opens and closes between
  /// tabs (ADR 0037). Without it, the row is there whenever [nowPlaying] is.
  final Animation<double>? row;

  const Dock({super.key, this.nowPlaying, required this.current, required this.onTab, this.selection, this.row});

  static const bindingKey = ValueKey('dock-binding');
  static const rowKey = ValueKey('dock-row');
  static const tabsKey = ValueKey('dock-tabs');
  static const barFillKey = ValueKey('dock-bar-fill');
  static const playDiscKey = ValueKey('dock-play-disc');
  static const pillKey = ValueKey('dock-pill');

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final np = nowPlaying;
    final row = this.row;
    return Container(
      key: bindingKey,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(color: c.cover, borderRadius: BorderRadius.circular(TzRadius.dock), boxShadow: c.dock),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (np != null)
            if (row == null) _NowPlayingRow(np) else _RowReveal(animation: row, child: _NowPlayingRow(np)),
          AnimatedBuilder(
            animation: row ?? kAlwaysCompleteAnimation,
            builder: (context, tabs) => Container(
              key: tabsKey,
              height: 54,
              decoration: BoxDecoration(
                  border: np == null || (row?.value ?? 1) == 0
                      ? null
                      : Border(top: BorderSide(color: c.coverLine.withValues(alpha: c.coverLine.a * (row?.value ?? 1))))),
              child: tabs,
            ),
            child: Semantics(
              container: true,
              label: 'التنقل',
              child: AnimatedBuilder(
                animation: selection ?? kAlwaysCompleteAnimation,
                builder: (context, _) => _tabs(c, selection?.value ?? current.index.toDouble()),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The four tabs with the selection at [at] (a tab's index, or between two).
  Widget _tabs(TzColors c, double at) {
    final n = DockTab.values.length;
    return LayoutBuilder(
      builder: (context, box) => Stack(
        fit: StackFit.expand,
        children: [
          Row(children: [
            for (final t in DockTab.values) Expanded(child: _tab(c, t, (1 - (at - t.index).abs()).clamp(0.0, 1.0))),
          ]),
          // The gilt lozenge under the selection, 4 px above the binding's edge.
          PositionedDirectional(
            start: box.maxWidth * (2 * at + 1) / (2 * n) - 10,
            width: 20,
            bottom: 5 - 1,
            child: IgnorePointer(child: Center(child: Lozenge(size: 5, radius: 1, color: c.giltOnCover))),
          ),
        ],
      ),
    );
  }

  /// Tab [t], [on] of the way to chosen (1 chosen, 0 not, between while gliding).
  Widget _tab(TzColors c, DockTab t, double on) {
    final ink = Color.lerp(c.coverMute, c.onCover, on)!;
    Widget icon(bool chosen) => TzIcon(chosen ? t.activeIcon : t.icon, filled: chosen, size: 21, color: ink);
    return MergeSemantics(
      child: Semantics(
        button: true,
        selected: t == current,
        child: TzPressable(
          sink: true,
          tint: c.onCover,
          onTap: () => onTab(t),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // The outline gives way to the filled glyph as the tab is chosen.
              if (on == 0 || on == 1)
                icon(on == 1)
              else
                Stack(children: [
                  Opacity(opacity: 1 - on, child: icon(false)),
                  Opacity(opacity: on, child: icon(true)),
                ]),
              const SizedBox(height: 2),
              Text(t.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TzType.caption.copyWith(
                      fontSize: 11.5, height: 16 / 11.5, color: ink, fontWeight: on >= 0.5 ? FontWeight.w600 : FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The now-playing row opening ([animation] 0 → 1) or closing over the tabs:
/// it grows from the tabs' edge and fades in as it does.
class _RowReveal extends AnimatedWidget {
  final Widget child;
  const _RowReveal({required Animation<double> animation, required this.child}) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final v = (listenable as Animation<double>).value;
    if (v <= 0) return const SizedBox.shrink();
    return ClipRect(
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: v,
        child: Opacity(opacity: v, child: child),
      ),
    );
  }
}

class _NowPlayingRow extends StatelessWidget {
  final NowPlaying np;
  const _NowPlayingRow(this.np);

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    final (Widget khatam, Widget title, String subtitle, List<Widget> actions) = switch (np) {
      NpPlaying(:final verse, :final position, :final subtitle, :final playing, :final onPrevious, :final onToggle, :final onNext) => (
          Khatam(verse, size: 42, onCover: true),
          Text.rich(
            TextSpan(text: 'البيت $verse ', children: [
              TextSpan(text: '· $position', style: TextStyle(color: c.coverMute, fontWeight: FontWeight.w500)),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _titleStyle(c.onCover),
          ),
          subtitle,
          [
            _IconButton(icon: 'prev', label: 'البيت السابق', color: c.onCover, onTap: onPrevious),
            _PlayButton(playing: playing, onTap: onToggle),
            _IconButton(icon: 'next', label: 'البيت التالي', color: c.onCover, onTap: onNext),
          ],
        ),
      NpNone(:final subtitle, :final action, :final onDownload) => (
          const Khatam('', size: 42, onCover: true),
          Text('استمع إلى المتن', maxLines: 1, overflow: TextOverflow.ellipsis, style: _titleStyle(c.onCover)),
          subtitle,
          [_PillButton(icon: 'down', label: action, onTap: onDownload)],
        ),
      NpDownloading(:final percent, :final progress, :final subtitle, :final onPause) => (
          Khatam(percent, size: 42, onCover: true, progress: progress),
          Text('جارٍ تنزيل التلاوة', maxLines: 1, overflow: TextOverflow.ellipsis, style: _titleStyle(c.onCover)),
          subtitle,
          [_IconButton(icon: 'pause', label: 'إيقاف مؤقت', color: c.onCover, onTap: onPause)],
        ),
      NpFailed(:final subtitle, :final onRetry) => (
          const Khatam('!', size: 42, onCover: true, error: true),
          Text('تعذّر التنزيل', maxLines: 1, overflow: TextOverflow.ellipsis, style: _titleStyle(c.errOnCover)),
          subtitle,
          [_PillButton(icon: 'retry', label: 'إعادة', onTap: onRetry)],
        ),
    };
    // Buttons drawn 44 px in 48 px targets: 2 px of target on each side, taken from the gaps.
    final endsInTarget = actions.last is! _PillButton;
    final onOpen = switch (np) { NpPlaying(:final onOpen) => onOpen, _ => null };
    final compact = switch (np) { NpPlaying(:final compactSubtitle) => compactSubtitle, _ => null };
    final meta = Row(
      children: [
        khatam,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              _Subtitle(subtitle, compact: compact, style: TzType.caption.copyWith(fontWeight: FontWeight.w400, color: c.coverMute)),
            ],
          ),
        ),
      ],
    );
    return SizedBox(
      key: Dock.rowKey,
      height: 62,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Padding(
            padding: EdgeInsetsDirectional.only(start: 10, end: endsInTarget ? 6 : 8),
            child: Row(
              children: [
                Expanded(
                  child: onOpen == null
                      ? meta
                      // One target for the whole row but its buttons: it opens the player.
                      : MergeSemantics(
                          child: Semantics(
                            button: true,
                            label: 'فتح المشغّل',
                            child: TzPressable(tint: TzTheme.of(context).colors.onCover, onTap: onOpen, child: SizedBox(height: 62, child: meta)),
                          ),
                        ),
                ),
                SizedBox(width: actions.first is _PillButton ? 10 : 8),
                ...actions,
              ],
            ),
          ),
          if (np case NpPlaying(:final progress, :final progressChanges))
            PositionedDirectional(start: 16, end: 16, bottom: 0, child: _Bar(progress, progressChanges)),
        ],
      ),
    );
  }

  static TextStyle _titleStyle(Color color) =>
      TzType.label.copyWith(fontSize: 14.5, height: 20 / 14.5, fontWeight: FontWeight.w600, color: color);
}

/// The row's second line. When the whole line does not fit and there is a
/// [compact] form, that is shown in its place; a screen reader still hears the whole line.
///
/// The line's numbers tick (the repeat count) and its digits differ in width, so
/// it is measured at its widest, every digit taken in turn for all of them: the
/// line does not change form from one repetition to the next.
class _Subtitle extends StatelessWidget {
  final String text;
  final String? compact;
  final TextStyle style;
  const _Subtitle(this.text, {required this.compact, required this.style});

  static final _digit = RegExp('[٠-٩0-9]');

  @override
  Widget build(BuildContext context) {
    final compact = this.compact;
    if (compact == null) return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    return LayoutBuilder(builder: (context, box) {
      final whole = TextPainter(
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      );
      final measured = DefaultTextStyle.of(context).style.merge(style);
      var fits = true;
      for (final d in '٠١٢٣٤٥٦٧٨٩'.split('')) {
        whole
          ..text = TextSpan(text: text.replaceAll(_digit, d), style: measured)
          ..layout();
        if (whole.width > box.maxWidth) {
          fits = false;
          break;
        }
      }
      whole.dispose();
      return Text(fits ? text : compact, semanticsLabel: fits ? null : text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style);
    });
  }
}

/// The section's progress: 2 px of gilt on the binding's hairline, from the start.
///
/// The recitation moving on is drawn as it comes: a step a listener cannot see
/// is not drawn at all, and a small one needs no animation. A jump (another
/// verse, a repeat going back, the section starting again) glides for 320 ms.
class _Bar extends StatefulWidget {
  final double progress;
  final Stream<double>? changes;
  const _Bar(this.progress, this.changes);

  /// A move smaller than this is not drawn: under half a pixel of the bar on any phone.
  static const double unseen = 0.0005;

  /// A move of up to this much is the recitation itself and is drawn at once.
  static const double step = 0.02;

  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> {
  late double _shown = widget.progress;
  bool _glide = false;
  StreamSubscription<double>? _changes;

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(_Bar old) {
    super.didUpdateWidget(old);
    _show(widget.progress);
    if (old.changes != widget.changes) {
      _changes?.cancel();
      _listen();
    }
  }

  void _listen() => _changes = widget.changes?.listen((p) {
        if (_show(p)) setState(() {});
      });

  /// Takes [progress] as what the bar shows; false when that changes nothing on screen.
  bool _show(double progress) {
    final move = progress - _shown;
    if (move == 0) return false;
    // The two ends are always drawn: the bar is empty at the start and full at the end.
    if (move.abs() < _Bar.unseen && progress > 0 && progress < 1) return false;
    _glide = move.abs() > _Bar.step;
    _shown = progress;
    return true;
  }

  @override
  void dispose() {
    _changes?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: Container(
          height: 2,
          color: c.coverLine,
          alignment: AlignmentDirectional.centerStart,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _shown.clamp(0, 1).toDouble()),
            duration: _glide ? tzDuration(context, TzMotion.long) : Duration.zero,
            curve: TzMotion.standard,
            builder: (_, p, _) => FractionallySizedBox(
              widthFactor: p,
              child: Container(key: Dock.barFillKey, height: 2, color: c.giltOnCover),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 44 px glyph button in a 48 px target (v2.css .ib).
class _IconButton extends StatelessWidget {
  final String icon, label;
  final Color color;
  final VoidCallback onTap;
  const _IconButton({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        onTap: onTap,
        child: TzPressable(sink: true, tint: TzTheme.of(context).colors.onCover,
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: SizedBox.square(
            dimension: TzSize.touchTarget,
            child: Center(child: TzIcon(icon, filled: true, size: 22, color: color)),
          ),
        ),
      );
}

/// Play or pause: a 44 px onCover disc in a 48 px target (v2.css .dplay).
class _PlayButton extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  const _PlayButton({required this.playing, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Semantics(
      button: true,
      label: playing ? 'إيقاف مؤقت' : 'تشغيل',
      excludeSemantics: true,
      onTap: onTap,
      child: TzPressable(circle: true, sink: true, tint: c.onCover,
        onTap: onTap,
        child: SizedBox.square(
          dimension: TzSize.touchTarget,
          child: Center(
            child: Container(
              key: Dock.playDiscKey,
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: c.onCover, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: TzFadeSwitcher(
                duration: TzMotion.short,
                child: TzIcon(playing ? 'pause' : 'play', key: ValueKey(playing), filled: true, size: 18, color: c.cover),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A 36 px pill (download, retry) in a 48 px target (v2.css .dbtn).
class _PillButton extends StatelessWidget {
  final String icon, label;
  final VoidCallback onTap;
  const _PillButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: TzPressable(sink: true, borderRadius: BorderRadius.circular(TzRadius.pill), tint: c.onCover,
          onTap: onTap,
          child: SizedBox(
            height: TzSize.touchTarget,
            child: Center(
              child: Container(
                key: Dock.pillKey,
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(color: c.onCover, borderRadius: BorderRadius.circular(TzRadius.pill)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  TzIcon(icon, size: 22, color: c.cover),
                  const SizedBox(width: 6),
                  Text(label, style: TzType.label.copyWith(fontSize: 13, fontWeight: FontWeight.w600, color: c.cover)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
