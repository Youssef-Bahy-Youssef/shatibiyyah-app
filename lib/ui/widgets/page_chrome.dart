// lib/ui/widgets/page_chrome.dart — the page-viewer chrome overlaid by the home screen:
// floating toolbar (.pv-toolbar: night / verse-boxes / zoom|search + brightness), the desktop
// page-nav arrows (.pv-nav), and the page-number indicator (.pv-pageno desktop pill /
// #immersive-page-indicator mobile). Ported from page-viewer.js _build() + style.css.
import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../utils/arabic.dart';
import 'page_viewer.dart';

class PageToolbar extends StatelessWidget {
  final PageViewerController controller;
  final bool isWide;
  const PageToolbar(
      {super.key, required this.controller, required this.isWide});

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        final tools = <Widget>[
          _tool(Icons.dark_mode_outlined, c.night,
              () => c.setNightMode(!c.night), 'الوضع الليلي'),
          _tool(Icons.view_agenda_outlined, c.showBoxes,
              () => c.setShowBoxes(!c.showBoxes), 'إظهار صناديق الأبيات'),
          if (isWide)
            _tool(Icons.zoom_in, false, () => c.toggleZoom(isWide),
                'تكبير / إعادة الضبط')
          else
            _tool(Icons.search, false, c.emitOpenSearch, 'بحث في الأبيات'),
        ];
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0x9E1A1208),
            border: Border.all(color: C.lineSoft),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...tools,
              if (c.night)
                SizedBox(
                  width: 116,
                  child: SliderTheme(
                    data: SliderThemeData(
                      trackHeight: 6,
                      activeTrackColor: C.gold,
                      inactiveTrackColor: C.line,
                      thumbColor: C.goldBright,
                      overlayShape: SliderComponentShape.noOverlay,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 8),
                    ),
                    child: Slider(
                      min: 50,
                      max: 110,
                      value: c.brightnessPct.toDouble(),
                      onChanged: (v) => c.setBrightness(v.round()),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _tool(IconData icon, bool pressed, VoidCallback onTap, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Semantics(
        label: label,
        button: true,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: pressed
                  ? const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [C.goldBright, C.gold])
                  : null,
            ),
            child: Icon(icon, size: 20, color: pressed ? C.onGold : C.parchDim),
          ),
        ),
      ),
    );
  }
}

class PageNavArrows extends StatelessWidget {
  final PageViewerController controller;
  const PageNavArrows({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    Widget arrow(String glyph, bool prev) => Align(
          alignment: prev ? Alignment.centerRight : Alignment.centerLeft,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: GestureDetector(
              onTap: () => controller.setPage(
                  controller.currentPage + (prev ? -1 : 1), true),
              child: Container(
                width: 44,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0x9E241A0C),
                  border: Border.all(color: C.line),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Text(glyph,
                    style: const TextStyle(
                        color: C.goldBright, fontSize: 25, height: 1)),
              ),
            ),
          ),
        );
    // .pv-prev{right} (›)  ·  .pv-next{left} (‹)
    return Stack(children: [arrow('›', true), arrow('‹', false)]);
  }
}

/// Page-number indicator. Desktop: a pill (.pv-pageno). Mobile: a faint indicator
/// (#immersive-page-indicator) that flashes brighter on page change.
class PageNoIndicator extends StatefulWidget {
  final PageViewerController controller;
  final bool isWide;
  const PageNoIndicator(
      {super.key, required this.controller, required this.isWide});

  @override
  State<PageNoIndicator> createState() => _PageNoIndicatorState();
}

class _PageNoIndicatorState extends State<PageNoIndicator> {
  int _lastPage = -1;
  bool _flash = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        if (c.currentPage != _lastPage && c.currentPage != 0) {
          _lastPage = c.currentPage;
          if (!widget.isWide) {
            _flash = true;
            Future.delayed(const Duration(milliseconds: 1800), () {
              if (mounted) setState(() => _flash = false);
            });
          }
        }
        final text =
            c.currentPage == 0 ? '' : '${ar(c.currentPage)} / ${ar(c.data.pageCount)}';
        if (widget.isWide) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xA81A1208),
              border: Border.all(color: C.lineSoft),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(text,
                style: ui(size: 11.84, color: C.parchDim, tabular: true)),
          );
        }
        // mobile immersive faint indicator
        return AnimatedOpacity(
          duration: const Duration(milliseconds: 400),
          opacity: _flash ? 0.70 : 0.12,
          child: Text(
            text,
            style: naskh(
                size: 13,
                color: c.night ? const Color(0x66FFAB2E) : const Color(0x8C2C1810)),
          ),
        );
      },
    );
  }
}
