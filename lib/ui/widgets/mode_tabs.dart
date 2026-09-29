// lib/ui/widgets/mode_tabs.dart — باب / نطاق / كل المتن tabs (.tabs / .tab).
// Ported from index.html (#tab-chapter/#tab-range/#tab-full) + style.css. Selected tab is
// gold-filled with the onGold text; the icon is an emoji as in the source.
import 'package:flutter/material.dart';

import '../../app_controller.dart';
import '../../theme.dart';

class ModeTabs extends StatelessWidget {
  final AppController app;
  const ModeTabs({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: app,
      builder: (context, _) {
        final mode = app.audio.mode;
        return Container(
          decoration: BoxDecoration(
            color: const Color(0x991A1208),
            border: Border.all(color: C.lineSoft),
            borderRadius: BorderRadius.circular(R.md),
          ),
          padding: const EdgeInsets.all(5),
          child: Row(
            children: [
              _tab('chapter', '📖', 'باب', mode),
              const SizedBox(width: 6),
              _tab('range', '🎯', 'نطاق', mode),
              const SizedBox(width: 6),
              _tab('full', '📚', 'كل المتن', mode),
            ],
          ),
        );
      },
    );
  }

  Widget _tab(String m, String ico, String label, String current) {
    final on = m == current;
    return Expanded(
      child: GestureDetector(
        onTap: () => app.setMode(m),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: const Cubic(.22, .61, .36, 1),
          constraints: const BoxConstraints(minHeight: 46),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(11),
            gradient: on
                ? const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [C.goldBright, C.gold])
                : null,
            boxShadow: on
                ? const [
                    BoxShadow(
                        color: Color(0xCCFFAB2E),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                        spreadRadius: -10)
                  ]
                : null,
          ),
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ico, style: const TextStyle(fontSize: 17.6, height: 1)),
              const SizedBox(height: 3),
              Text(label,
                  style: kufi(
                      size: 14.72,
                      weight: 600,
                      color: on ? C.onGold : C.parchDim)),
            ],
          ),
        ),
      ),
    );
  }
}
