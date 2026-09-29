// lib/ui/shell/boot_splash.dart — the launch splash (features-v3 boot-splash).
//
// The logo on espresso, «تيسير الشاطبية» and «حِرْزُ الأَمَانِي وَوَجْهُ التَّهَانِي»; always
// dark, whatever the theme. It covers loading for at least 1200 ms, then fades in
// 400 ms. A thin progress line and «يعمل دون اتصال» appear only when loading takes
// longer than 2 s. A tap skips the minimum wait (never the loading itself).
//
// [child] stays at a fixed place in the tree underneath, so the app below is never
// rebuilt from scratch when the splash goes.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme.dart' show kufi, naskh;
import '../design/taysir_logo.dart';

const Duration kSplashMinimum = Duration(milliseconds: 1200);
const Duration kSplashFade = Duration(milliseconds: 400);
const Duration kSplashSlow = Duration(seconds: 2);

class BootSplash extends StatefulWidget {
  /// Whether whatever the splash covers has finished loading.
  final bool ready;
  final Widget child;
  const BootSplash({super.key, required this.ready, required this.child});

  @override
  State<BootSplash> createState() => _BootSplashState();
}

class _BootSplashState extends State<BootSplash> {
  bool _minimumDone = false;
  bool _slow = false;
  bool _gone = false;
  late final Timer _minimum;
  late final Timer _slowTimer;

  @override
  void initState() {
    super.initState();
    _minimum = Timer(kSplashMinimum, _skip);
    _slowTimer = Timer(kSplashSlow, () {
      if (mounted && !widget.ready) setState(() => _slow = true);
    });
  }

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
    final leaving = widget.ready && _minimumDone;
    return Stack(
      children: [
        widget.child,
        if (!_gone)
          AnimatedOpacity(
            opacity: leaving ? 0 : 1,
            duration: kSplashFade,
            onEnd: () {
              if (leaving && mounted) setState(() => _gone = true);
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
      ],
    );
  }
}

class _SplashFace extends StatelessWidget {
  final bool slow;
  const _SplashFace({required this.slow});

  @override
  Widget build(BuildContext context) {
    // Always dark, so the status bar icons stay light whatever the theme.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.24),
              radius: 1.1,
              colors: [Color(0xFF3F2F15), Color(0xFF1B1307), Color(0xFF120C05)],
              stops: [0, 0.62, 1],
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const TaysirLogo(size: 176),
                  const SizedBox(height: 26),
                  Text('تيسير الشاطبية', style: kufi(size: 30, weight: 600, color: const Color(0xFFFADBAE))),
                  const SizedBox(height: 6),
                  Text(
                    'حِرْزُ الأَمَانِي وَوَجْهُ التَّهَانِي',
                    style: naskh(size: 18, color: const Color(0xFFD6CCB8)),
                  ),
                ],
              ),
              if (slow)
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
                          child: const LinearProgressIndicator(
                            color: Color(0xFFFFAB2E),
                            backgroundColor: Color(0xFF4A3719),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'يعمل دون اتصال',
                        style: kufi(size: 12, weight: 400, color: const Color(0xFFB39A6B)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
