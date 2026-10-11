// lib/ui/shell/boot_splash.dart — the launch splash (features-v3 boot-splash).
//
// The logo on the night ground, «تيسير الشاطبية» and «حِرْزُ الأَمَانِي وَوَجْهُ التَّهَانِي»;
// always dark, whatever the theme. It covers loading for at least 1200 ms, then
// fades in 400 ms. A thin progress line and «يعمل دون اتصال» appear only when
// loading takes longer than 2 s. A tap skips the minimum wait (never the loading
// itself).
//
// It starts to lift a frame after what it covers was first built, so the heaviest
// frame of the launch is drawn under it, not in the fade; and the status bar's
// icons become the app's as the fade begins, not with a snap at its end.
//
// It takes over from the platform's launch screen, which can only draw the logo
// on a flat ground: its first frame is that same picture, and it settles into its
// own (the larger logo, the name under it, the glow behind) in 320 ms, so nothing
// jumps when Flutter's first frame replaces the launch screen.
//
// [child] stays at a fixed place in the tree underneath, so the app below is never
// rebuilt from scratch when the splash goes.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design/components/tz_motion.dart';
import '../design/tokens.g.dart';
import '../design/taysir_logo.dart';

const Duration kSplashMinimum = Duration(milliseconds: 1200);
const Duration kSplashFade = Duration(milliseconds: 400);
const Duration kSplashSlow = Duration(seconds: 2);

/// The logo on the platform's launch screen: 134.4 px, in the middle of the
/// screen, on the night ground. Android from 12 shows the adaptive icon's
/// foreground there, its 108 dp layer at 288 dp, and the mark is 70 % of that
/// layer's 72 dp window (ADR 0028; tool/render_brand_assets.dart).
/// launch_background.xml draws the same size before 12. The splash begins as that
/// picture.
const double kLaunchLogoSize = 72 * (1 - 2 * TaysirLogoPainter.tileInset) * 288 / 108;

/// The logo on the splash once it has settled.
const double kSplashLogoSize = 176;

class BootSplash extends StatefulWidget {
  /// Whether whatever the splash covers has finished loading.
  final bool ready;
  final Widget child;

  /// Called once the splash has faded out (e.g. to open the first-run tour).
  final VoidCallback? onGone;
  const BootSplash({super.key, required this.ready, required this.child, this.onGone});

  @override
  State<BootSplash> createState() => _BootSplashState();
}

class _BootSplashState extends State<BootSplash> {
  bool _minimumDone = false;
  bool _slow = false;
  bool _gone = false;

  /// What the splash covers has been on the screen for a frame.
  bool _drawn = false;
  late final Timer _minimum;
  late final Timer _slowTimer;

  @override
  void initState() {
    super.initState();
    _minimum = Timer(kSplashMinimum, _skip);
    _slowTimer = Timer(kSplashSlow, () {
      if (mounted && !widget.ready) setState(() => _slow = true);
    });
    if (widget.ready) _coveredIsBuilt();
  }

  @override
  void didUpdateWidget(BootSplash old) {
    super.didUpdateWidget(old);
    if (widget.ready && !old.ready) _coveredIsBuilt();
  }

  void _coveredIsBuilt() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _drawn = true);
      });

  void _skip() {
    if (mounted && !_minimumDone) setState(() => _minimumDone = true);
  }

  @override
  void dispose() {
    _minimum.cancel();
    _slowTimer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final leaving = widget.ready && _minimumDone && _drawn;
    return Stack(
      children: [
        widget.child,
        if (!_gone)
          AnimatedOpacity(
            opacity: leaving ? 0 : 1,
            duration: kSplashFade,
            curve: TzMotion.exit,
            onEnd: () {
              if (leaving && mounted) {
                setState(() => _gone = true);
                widget.onGone?.call();
              }
            },
            child: IgnorePointer(
              ignoring: leaving,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _skip,
                // Above the app's Scaffold: without a Material the text gets the debug underline.
                child: Material(
                  type: MaterialType.transparency,
                  child: _SplashFace(slow: _slow && !widget.ready),
                ),
              ),
            ),
          ),
        // Always dark, so the status bar's icons are light whatever the theme, until
        // the splash starts to lift.
        if (!leaving && !_gone)
          const IgnorePointer(
            child: AnnotatedRegion<SystemUiOverlayStyle>(value: SystemUiOverlayStyle.light, child: SizedBox.expand()),
          ),
      ],
    );
  }
}

class _SplashFace extends StatefulWidget {
  final bool slow;
  const _SplashFace({required this.slow});

  @override
  State<_SplashFace> createState() => _SplashFaceState();
}

class _SplashFaceState extends State<_SplashFace> with SingleTickerProviderStateMixin {
  // From the launch screen's picture (0) to the splash's own (1).
  late final AnimationController _settle = AnimationController(vsync: this);
  late final Animation<double> _settled = CurvedAnimation(parent: _settle, curve: TzMotion.emphasized);
  late final Animation<double> _logoScale =
      Tween<double>(begin: kLaunchLogoSize / kSplashLogoSize, end: 1).animate(_settled);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Under reduced motion the splash stands as drawn from its first frame.
    _settle
      ..duration = tzDuration(context, TzMotion.long)
      ..forward();
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ColoredBox(
        color: TzColors.night.bg,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // The glow behind the logo comes up with the name.
            FadeTransition(
              opacity: _settled,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, -0.24),
                    radius: 1.1,
                    colors: [TzColors.night.raised, TzColors.night.bg, TzColors.night.bg],
                    stops: const [0, 0.62, 1],
                  ),
                ),
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ScaleTransition(scale: _logoScale, child: const TaysirLogo(size: kSplashLogoSize)),
                // The name opens out from under the logo. While it has no height the
                // logo alone is centred, where the launch screen drew it. Nothing is
                // clipped: the marks under the last line reach past its box.
                AnimatedBuilder(
                  animation: _settled,
                  builder: (context, child) =>
                      Align(alignment: Alignment.topCenter, heightFactor: _settled.value, child: child),
                  child: FadeTransition(
                    opacity: _settled,
                    child: Column(
                      children: [
                        const SizedBox(height: 26),
                        Text('تيسير الشاطبية', style: TzType.display.copyWith(color: TzColors.night.ink)),
                        const SizedBox(height: 6),
                        Text(
                          'حِرْزُ الأَمَانِي وَوَجْهُ التَّهَانِي',
                          style: TzType.chapter.copyWith(color: TzColors.night.ink2),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (widget.slow)
              Positioned(
                left: 0,
                right: 0,
                bottom: 56 + MediaQuery.of(context).padding.bottom,
                child: Column(
                  children: [
                    SizedBox(
                      width: 96,
                      height: 3,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          color: TzColors.night.action,
                          backgroundColor: TzColors.night.line,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'يعمل دون اتصال',
                      style: TzType.caption.copyWith(color: TzColors.night.ink3),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
