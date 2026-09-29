// lib/ui/widgets/playback_controls.dart — the main transport (.transport): prev · play ·
// stop · next. Ported from index.html (#prevBtn/#playBtn/#stopBtn/#nextBtn) + style.css
// (.tbtn outlined gold rings; .tbtn.play gold-filled, larger). Icons match the SVG paths.
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../theme.dart';
import 'svg_icons.dart';

class PlaybackControls extends StatelessWidget {
  final AppController app;
  final bool compact; // mobile sizing
  const PlaybackControls({super.key, required this.app, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final tbtn = compact ? 48.0 : 54.0;
    final ticon = compact ? 21.0 : 23.0;
    final pbtn = compact ? 60.0 : 70.0;
    final picon = compact ? 25.0 : 28.0;
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) => Directionality(
        textDirection: TextDirection.ltr, // .transport{direction:ltr}
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ring(size: tbtn, icon: SvgIcon.prev, iconSize: ticon, onTap: app.prev, label: 'البيت السابق'),
            const SizedBox(width: 14),
            _play(size: pbtn, iconSize: picon),
            const SizedBox(width: 14),
            _ring(size: tbtn, icon: SvgIcon.stop, iconSize: ticon, onTap: app.doStop, label: 'إيقاف والعودة إلى البداية'),
            const SizedBox(width: 14),
            _ring(size: tbtn, icon: SvgIcon.next, iconSize: ticon, onTap: app.next, label: 'البيت التالي'),
          ],
        ),
      ),
    );
  }

  Widget _ring({
    required double size,
    required SvgIcon icon,
    required double iconSize,
    required VoidCallback onTap,
    required String label,
  }) {
    return _Pressable(
      onTap: onTap,
      builder: (pressed) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: const Color(0x0DFFAB2E), // rgba(255,171,46,.05)
          border: Border.all(color: C.goldDeep, width: 1.5),
        ),
        alignment: Alignment.center,
        child: SvgIconWidget(icon, size: iconSize, color: C.goldBright),
      ),
    );
  }

  Widget _play({required double size, required double iconSize}) {
    return _Pressable(
      onTap: app.togglePlay,
      builder: (pressed) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [C.goldBright, C.gold],
          ),
          border: Border.all(color: C.goldBright, width: 1.5),
          boxShadow: const [
            BoxShadow(color: Color(0xD9FFAB2E), blurRadius: 28, offset: Offset(0, 12), spreadRadius: -10),
          ],
        ),
        alignment: Alignment.center,
        child: SvgIconWidget(
          app.isPaused ? SvgIcon.play : SvgIcon.pause,
          size: iconSize,
          color: C.onGold,
        ),
      ),
    );
  }
}

/// Press-scale wrapper (CSS :active{transform:scale(.9)}).
class _Pressable extends StatefulWidget {
  final VoidCallback onTap;
  final Widget Function(bool pressed) builder;
  const _Pressable({required this.onTap, required this.builder});
  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _p = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _p = true),
      onTapUp: (_) => setState(() => _p = false),
      onTapCancel: () => setState(() => _p = false),
      child: AnimatedScale(
        scale: _p ? 0.9 : 1,
        duration: const Duration(milliseconds: 100),
        child: widget.builder(_p),
      ),
    );
  }
}
