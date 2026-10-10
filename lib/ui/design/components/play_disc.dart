// lib/ui/design/components/play_disc.dart — the player's play or pause (item
// 3.7; v2.css .bigplay): a 72 px disc in the action colour with a filled glyph
// and a soft lapis shadow.
import 'package:flutter/material.dart';

import '../tz_icon.dart';
import '../tz_theme.dart';

class PlayDisc extends StatelessWidget {
  final bool playing;
  final VoidCallback onTap;
  const PlayDisc({super.key, required this.playing, required this.onTap});

  /// v2.css .bigplay: box-shadow 0 6px 16px rgba(23,42,82,.25).
  static const _shadow = [BoxShadow(color: Color(0x40172A52), offset: Offset(0, 6), blurRadius: 16)];

  @override
  Widget build(BuildContext context) {
    final c = TzTheme.of(context).colors;
    return Semantics(
      button: true,
      label: playing ? 'إيقاف مؤقت' : 'تشغيل',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 72,
          height: 72,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: c.action, shape: BoxShape.circle, boxShadow: _shadow),
          child: TzIcon(playing ? 'pause' : 'play', filled: true, size: 28, color: c.onAction),
        ),
      ),
    );
  }
}
