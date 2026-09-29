// lib/ui/widgets/mini_bar.dart — mobile bottom chrome: the range-status card (#range-status-card)
// + the compact 3-state audio bar (.cp-bar: idle / playing / paused). Ported from index.html +
// style.css. Idle = gear · spacer · verse-info · ▶ (far right); playing/paused = gear · transport
// · verse-info + a seek row below. Tapping the bar opens the console sheet.
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../theme.dart';
import '../../utils/arabic.dart';
import 'progress_bar.dart';
import 'svg_icons.dart';

class RangeStatusCard extends StatelessWidget {
  final AppController app;
  const RangeStatusCard({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final s = app.rangeStatus();
        return GestureDetector(
          onTap: app.openRangeSheet,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: const BoxDecoration(
              color: C.panel,
              border: Border(top: BorderSide(color: C.goldDeep)),
            ),
            child: Row(
              children: [
                _circle(child: Text(s.icon, style: const TextStyle(fontSize: 22))),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(s.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: naskh(size: 15, weight: FontWeight.w500, color: C.gold)),
                      const SizedBox(height: 1),
                      Text(s.sub,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: ui(size: 12, color: const Color(0xA6FFFFFF), tabular: true)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                _circle(
                    child: Text('▼',
                        style: TextStyle(color: C.gold, fontSize: 13, height: 1))),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _circle({required Widget child}) => Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: C.gold, width: 1.5),
        ),
        alignment: Alignment.center,
        child: child,
      );
}

class MiniBar extends StatelessWidget {
  final AppController app;
  const MiniBar({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final state = app.barState; // idle | playing | paused
        final showTransport = state == 'playing' || state == 'paused';
        return GestureDetector(
          onTap: app.toggleConsole,
          child: Container(
            padding: EdgeInsets.fromLTRB(12, 0, 12, mq.padding.bottom),
            decoration: const BoxDecoration(
              color: C.ink2,
              border: Border(top: BorderSide(color: C.goldDeep)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 66,
                  // RTL flow (HTML order: idle-play · info · transport · gear):
                  // idle-play far right, gear far left.
                  child: Row(
                    children: [
                      if (state == 'idle') ...[
                        // No recording on the device yet (nothing is bundled): say so
                        // instead of offering a play button that cannot play.
                        if (app.audioAvailable)
                          _miniBtn(SvgIcon.play, 48, 20, app.togglePlay)
                        else
                          _noAudio(),
                        const SizedBox(width: 10),
                      ],
                      // verse info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text.rich(
                              TextSpan(children: [
                                const TextSpan(text: 'البيت '),
                                TextSpan(
                                    text: ar(app.currentVerse),
                                    style: ui(
                                        size: 16.8,
                                        weight: FontWeight.w700,
                                        color: C.gold)),
                              ], style: ui(size: 11.2, color: C.gold)),
                            ),
                            Text(
                                app.chapterName.isEmpty ? '—' : app.chapterName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: naskh(size: 16.32, color: C.parch)),
                          ],
                        ),
                      ),
                      if (showTransport) ...[
                        const SizedBox(width: 10),
                        _transport(),
                      ],
                      const SizedBox(width: 10),
                      // gear (far left in RTL) → opens the console
                      _miniGear(),
                    ],
                  ),
                ),
                // seek row (expands when playing/paused)
                AnimatedSize(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: showTransport
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: ProgressBar(app: app, mini: true),
                        )
                      : const SizedBox(width: double.infinity),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _noAudio() => Semantics(
        label: 'التلاوة غير متاحة بعد',
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: C.line),
          ),
          child: Text('التلاوة قريبًا', style: kufi(size: 13, weight: 500, color: C.muted)),
        ),
      );

  Widget _miniGear() => _tapStop(
        onTap: app.toggleConsole,
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: C.gold, width: 1.5),
          ),
          alignment: Alignment.center,
          child: const Icon(Icons.settings, size: 21, color: C.gold),
        ),
      );

  Widget _transport() => Directionality(
        textDirection: TextDirection.ltr, // .mini-transport{direction:ltr}
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _miniBtn(SvgIcon.prev, 42, 18, app.prev),
            const SizedBox(width: 8),
            _miniBtn(SvgIcon.stop, 42, 18, app.doStop),
            const SizedBox(width: 8),
            _miniBtn(app.isPaused ? SvgIcon.play : SvgIcon.pause, 44, 19,
                app.togglePlay),
            const SizedBox(width: 8),
            _miniBtn(SvgIcon.next, 42, 18, app.next),
          ],
        ),
      );

  Widget _miniBtn(SvgIcon icon, double size, double iconSize, VoidCallback onTap) {
    return _tapStop(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: C.gold, width: 1.5),
        ),
        alignment: Alignment.center,
        child: SvgIconWidget(icon, size: iconSize, color: C.gold),
      ),
    );
  }

  // stop tap from bubbling to the bar's open-console gesture
  Widget _tapStop({required VoidCallback onTap, required Widget child}) =>
      GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      );
}
