// lib/ui/design/components/tz_motion.dart — motion that honours reduced motion.
//
// Every component animates with the token durations and curves (tokens.json
// motion) and is instant when the platform asks for reduced motion
// (MediaQuery.disableAnimations), as the spec says: "everything instant".
//
// ADR 0037 adds what the design left out and a first tester missed: a tap that
// answers the finger ([TzPressable]), things that leave as softly as they came
// ([TzPresence], [TzFadeSwitcher]), and pushed screens that move the way the
// app reads, right to left ([TzPageTransitionsBuilder]).
import 'package:flutter/material.dart';

import '../tokens.g.dart';
import '../tz_theme.dart';

/// [d], or zero under reduced motion.
Duration tzDuration(BuildContext context, Duration d) =>
    MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;

/// Whether [context] asks for no motion.
bool tzReduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) == true;

/// A tap target that answers the finger (ADR 0037). Pressed, a soft tint of the
/// ink comes over it in 120 ms and, for a compact control ([sink]), it settles
/// to 96 %; released, both go in 200 ms. A quick tap still shows the whole press.
///
/// A drop-in for the app's InkWells: the same [onTap], [onLongPress] and
/// [borderRadius]. The tint is drawn over the child, so it shows on a filled
/// surface too, where an ink splash would be painted underneath and hidden.
class TzPressable extends StatefulWidget {
  final VoidCallback? onTap, onLongPress;
  final BorderRadius? borderRadius;

  /// Round, like a disc button (else [borderRadius], else square).
  final bool circle;

  /// The tint's colour at full strength; the theme's ink by default.
  final Color? tint;

  /// Settles to 96 % while pressed: for buttons, chips and tabs, not for rows.
  final bool sink;
  final Widget child;

  const TzPressable(
      {super.key,
      this.onTap,
      this.onLongPress,
      this.borderRadius,
      this.circle = false,
      this.tint,
      this.sink = false,
      required this.child});

  /// How much of the tint colour the pressed state shows.
  static const double tintAlpha = 0.09;

  /// How far a sinking control settles.
  static const double sinkScale = 0.96;

  @override
  State<TzPressable> createState() => _TzPressableState();
}

class _TzPressableState extends State<TzPressable> with SingleTickerProviderStateMixin {
  late final AnimationController _press =
      AnimationController(vsync: this, duration: TzMotion.short, reverseDuration: TzMotion.medium);
  late final Animation<double> _t = CurvedAnimation(parent: _press, curve: TzMotion.standard);
  bool _down = false;

  void _highlight(bool down) {
    _down = down;
    if (tzReduced(context)) {
      _press.value = down ? 1 : 0;
    } else if (down) {
      _press.forward();
    } else if (_press.status == AnimationStatus.forward) {
      // A quick tap: the press is shown in full, then let go.
      _press.forward().whenCompleteOrCancel(() {
        if (!_down && mounted) _press.reverse();
      });
    } else {
      _press.reverse();
    }
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tint = (widget.tint ?? TzTheme.of(context).colors.ink).withValues(alpha: TzPressable.tintAlpha);
    final radius = widget.borderRadius;
    return InkWell(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      onHighlightChanged: _highlight,
      splashFactory: NoSplash.splashFactory,
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      borderRadius: radius,
      customBorder: widget.circle ? const CircleBorder() : null,
      child: AnimatedBuilder(
        animation: _t,
        // The same two wrappers pressed or not, so what is inside keeps its state.
        builder: (context, child) {
          final t = _t.value;
          return CustomPaint(
            foregroundPainter:
                t == 0 ? null : _PressTint(tint.withValues(alpha: tint.a * t), circle: widget.circle, radius: radius),
            child: Transform.scale(scale: widget.sink ? 1 - (1 - TzPressable.sinkScale) * t : 1, child: child),
          );
        },
        child: widget.child,
      ),
    );
  }
}

class _PressTint extends CustomPainter {
  final Color color;
  final bool circle;
  final BorderRadius? radius;
  const _PressTint(this.color, {required this.circle, this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final rect = Offset.zero & size;
    if (circle) {
      canvas.drawCircle(rect.center, size.shortestSide / 2, paint);
    } else if (radius case final r?) {
      canvas.drawRRect(r.toRRect(rect), paint);
    } else {
      canvas.drawRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_PressTint old) => old.color != color || old.circle != circle || old.radius != radius;
}

/// Shows [child] while it is not null, and when it goes (null) keeps the last one
/// a moment to fade it out in 160 ms (ADR 0037). What enters brings its own
/// motion (a popover grows, a sheet rises), so entering is not touched unless
/// [fadeIn]. A new [id] is a new child (its own entrance); the same id coming
/// back while it fades out takes it back where it is. There is only ever one
/// child, so one that holds a GlobalKey can come and go.
class TzPresence extends StatefulWidget {
  final Widget? child;
  final Object? id;
  final bool fadeIn;

  /// How far it slides (dp, downward) as it fades, entering and leaving.
  final double travel;

  /// How long a [fadeIn] entrance takes; a long one is emphasized.
  final Duration enter;

  const TzPresence(
      {super.key, required this.child, this.id, this.fadeIn = false, this.travel = 0, this.enter = TzMotion.medium});

  static const exitDuration = Duration(milliseconds: 160);

  @override
  State<TzPresence> createState() => _TzPresenceState();
}

class _TzPresenceState extends State<TzPresence> with SingleTickerProviderStateMixin {
  late final AnimationController _shown;
  Widget? _child;
  Object? _id;

  /// Which child this is: a new one gets a new element.
  int _key = 0;

  /// Bumped when something comes back, so a fade-out that was under way does not end it.
  int _exit = 0;

  Widget? _keep() {
    _id = widget.id;
    return widget.child;
  }

  @override
  void initState() {
    super.initState();
    // What is there from the first frame is simply there: only arrivals move.
    _shown = AnimationController(vsync: this, value: widget.child == null ? 0 : 1);
    _child = _keep();
  }

  void _show({double? from}) {
    if (!mounted) return;
    if (tzReduced(context)) {
      _shown.value = 1;
      return;
    }
    if (from != null) _shown.value = from;
    _shown.animateTo(1,
        duration: widget.fadeIn ? widget.enter : TzMotion.short,
        curve: widget.enter == TzMotion.long ? TzMotion.emphasized : TzMotion.standard);
  }

  @override
  void didUpdateWidget(TzPresence old) {
    super.didUpdateWidget(old);
    final child = widget.child;
    if (child == null) {
      if (_child == null) return;
      // Leaving: kept until it has faded.
      if (tzReduced(context)) {
        setState(() => _child = null);
        _shown.value = 0;
        return;
      }
      final exit = ++_exit;
      _shown.animateTo(0, duration: TzPresence.exitDuration, curve: TzMotion.exit).whenCompleteOrCancel(() {
        // Let go after this frame is built: the same child may be coming back in it.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && exit == _exit && widget.child == null) setState(() => _child = null);
        });
      });
      return;
    }
    final fresh = _child == null || widget.id != _id;
    if (fresh) _key++;
    _exit++;
    final wasHidden = _child == null;
    _child = _keep();
    if (fresh && !wasHidden) {
      // Another one in its place: shown at once, with its own entrance.
      _shown.value = widget.fadeIn ? 0 : 1;
      if (widget.fadeIn) _show();
    } else if (wasHidden) {
      _show(from: widget.fadeIn ? 0 : 1);
    } else if (_shown.status == AnimationStatus.reverse || _shown.value < 1) {
      _show(); // back before it had gone
    }
  }

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = _child;
    if (child == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: _shown,
      child: KeyedSubtree(key: ValueKey(('presence', _key)), child: child),
      builder: (context, child) {
        final t = _shown.value;
        final leaving = widget.child == null;
        if (leaving && t == 0) return const SizedBox.shrink(); // gone, in the frame it ends
        return IgnorePointer(
          // A leaving overlay no longer takes touches: the next tap reaches what is under it.
          ignoring: leaving,
          child: Opacity(
            opacity: t.clamp(0.0, 1.0),
            child: Transform.translate(offset: Offset(0, widget.travel * (1 - t)), child: child),
          ),
        );
      },
    );
  }
}

/// [builder] given [color], easing from the last colour to it in 200 ms (ADR 0037):
/// a choice's fill and ink move to it instead of jumping. The first build is the
/// colour itself.
class TzColorTween extends StatelessWidget {
  final Color color;
  final Widget Function(BuildContext context, Color color, Widget? child) builder;
  final Widget? child;
  const TzColorTween({super.key, required this.color, required this.builder, this.child});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: color),
        duration: tzDuration(context, TzMotion.medium),
        curve: TzMotion.standard,
        builder: (context, value, child) => builder(context, value ?? color, child),
        child: child,
      );
}

/// A cross-fade between one child and the next (ADR 0037): the new one fades in
/// over 200 ms as the old one fades out. For a word, an icon or a whole panel
/// that is replaced in place.
class TzFadeSwitcher extends StatelessWidget {
  final Widget child;
  final Duration duration;
  final AlignmentGeometry alignment;
  const TzFadeSwitcher({super.key, required this.child, this.duration = TzMotion.medium, this.alignment = Alignment.center});

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
        duration: tzDuration(context, duration),
        switchInCurve: TzMotion.standard,
        switchOutCurve: TzMotion.exit,
        layoutBuilder: (current, previous) =>
            Stack(alignment: alignment, children: [...previous, ?current]),
        // Opacity, not FadeTransition: at rest it paints straight through, with no
        // layer of its own, so a still screen is drawn exactly as before.
        transitionBuilder: (child, animation) => _Fade(animation: animation, child: child),
        child: child,
      );
}

class _Fade extends AnimatedWidget {
  final Widget child;
  const _Fade({required Animation<double> animation, required this.child}) : super(listenable: animation);

  @override
  Widget build(BuildContext context) => Opacity(opacity: (listenable as Animation<double>).value, child: child);
}

/// The pushed screen's motion on Android (ADR 0037): the shared horizontal axis
/// of Material motion, mirrored for a right-to-left app as iOS mirrors its own.
/// Going forward, the new screen comes in from 30 dp on the left as it fades in,
/// and the one below moves 30 dp to the right as it fades out; back is the same
/// in reverse. 320 ms, emphasized. Flutter's own Android default slides the
/// left-to-right way whatever the language.
class TzPageTransitionsBuilder extends PageTransitionsBuilder {
  const TzPageTransitionsBuilder();

  static const double travel = 30;

  @override
  Duration get transitionDuration => TzMotion.long;

  @override
  Duration get reverseTransitionDuration => TzMotion.long;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (tzReduced(context)) return child;
    return _SharedAxis(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      background: TzTheme.of(context).colors.bg,
      child: child,
    );
  }
}

class _SharedAxis extends StatelessWidget {
  final Animation<double> animation, secondaryAnimation;
  final Color background;
  final Widget child;
  const _SharedAxis({required this.animation, required this.secondaryAnimation, required this.background, required this.child});

  // Material's fade-through: the screen leaving fades in the first 30 % of the
  // time, the one arriving in the remaining 70 %; both slide the whole time.
  // The intervals are over each animation's value, which runs back on a pop.
  static const _arrive = Interval(0.3, 1, curve: TzMotion.standard); // pushed: value 0.3 → 1
  static const _leaveOnPop = Interval(0.7, 1, curve: TzMotion.exit); // popped: value 1 → 0.7
  static const _cover = Interval(0, 0.3, curve: TzMotion.exit); // covered: value 0 → 0.3
  static const _uncover = Interval(0, 0.7, curve: TzMotion.standard); // uncovered: value 0.7 → 0

  @override
  Widget build(BuildContext context) {
    // Mirrored in right-to-left: the new screen comes from the left.
    final sign = Directionality.of(context) == TextDirection.rtl ? -1.0 : 1.0;
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      child: child,
      builder: (context, child) {
        final a = animation.value, s = secondaryAnimation.value;
        // Arriving: from +travel to 0. Covered by the next screen: from 0 to -travel.
        final dx = sign * TzPageTransitionsBuilder.travel * ((1 - TzMotion.emphasized.transform(a)) - TzMotion.emphasized.transform(s));
        final own = switch (animation.status) {
          AnimationStatus.forward => _arrive.transform(a),
          AnimationStatus.reverse => _leaveOnPop.transform(a),
          _ => a,
        };
        final below = switch (secondaryAnimation.status) {
          AnimationStatus.forward => 1 - _cover.transform(s),
          AnimationStatus.reverse => 1 - _uncover.transform(s),
          _ => 1 - s,
        };
        Widget w = Opacity(
          opacity: (own * below).clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(dx, 0), child: child),
        );
        // A screen fading out from under the next one shows the ground, not a hole.
        if (secondaryAnimation.isAnimating) w = ColoredBox(color: background, child: w);
        return w;
      },
    );
  }
}
