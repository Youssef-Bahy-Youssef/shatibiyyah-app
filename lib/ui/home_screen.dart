// lib/ui/home_screen.dart — responsive shell. Port of the index.html body layout + the
// mobile immersive behaviour from style.css/app.js. Desktop (≥1025px): side controls panel
// (right, RTL) + page viewer. Mobile: full-screen page viewer with sliding immersive chrome
// (top toolbar + bottom range-card + mini bar), an expandable console sheet, a range-selector
// sheet, a full-screen search overlay, picker sheet, and the floating resume chip.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../theme.dart';
import 'widgets/advanced_controls_sheet.dart';
import 'widgets/console_panel.dart';
import 'widgets/mini_bar.dart';
import 'widgets/page_chrome.dart';
import 'widgets/page_viewer.dart';
import 'widgets/range_selector.dart';
import 'widgets/sync_controls.dart';
import 'widgets/verse_menu.dart';
import 'widgets/verse_text_overlay.dart';

class HomeScreen extends StatefulWidget {
  final AppController app;
  const HomeScreen({super.key, required this.app});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppController get app => widget.app;
  double _consoleDrag = 0;
  double _rangeDrag = 0;

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: C.ink2,
      systemNavigationBarIconBrightness: Brightness.light,
    ));
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final wide = MediaQuery.of(context).size.width >= 1025;
      app.initImmersive(wide);
      await app.boot();
      if (mounted) setState(() {});
    });
  }

  double _chromeHeight() {
    final mq = MediaQuery.of(context);
    double h = mq.padding.bottom + 64 /*range card*/ + 66 /*mini bar*/;
    if (app.barState == 'playing' || app.barState == 'paused') h += 34;
    if (app.selectedChapter != null) h += 66;
    return h;
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 1025;
    if (app.wide != wide) {
      WidgetsBinding.instance.addPostFrameCallback((_) => app.initImmersive(wide));
    }
    return Scaffold(
      backgroundColor: C.ink,
      body: AnimatedBuilder(
        animation: app,
        builder: (context, _) => wide ? _desktop() : _mobile(),
      ),
    );
  }

  // ───────────────────────── desktop ─────────────────────────
  Widget _desktop() {
    final mq = MediaQuery.of(context);
    final panelW = (mq.size.width * 0.34).clamp(320.0, 430.0);
    return Stack(
      children: [
        Row(
          children: [
            // controls panel (order:1 → RTL start = right)
            Container(
              width: panelW,
              height: double.infinity,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x8C2A1E0E), Color(0x8C241A0C)],
                ),
                border: Border(left: BorderSide(color: C.goldDeep)),
              ),
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    20, mq.padding.top + 20, 20, mq.padding.bottom + 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ChapterActionBand(app: app),
                    ConsoleBody(app: app, wide: true),
                  ],
                ),
              ),
            ),
            Expanded(child: _viewerStack(wide: true)),
          ],
        ),
        PickerSheet(app: app),
        VerseMenu(app: app),
      ],
    );
  }

  // ───────────────────────── mobile ─────────────────────────
  Widget _mobile() {
    final hidden = app.controlsHidden;
    final chromeH = _chromeHeight();
    return Stack(
      children: [
        // page viewer fills; insets above the chrome when controls visible
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
          top: 0,
          left: 0,
          right: 0,
          bottom: hidden ? 0 : chromeH,
          child: PageViewer(controller: app.viewer),
        ),
        // immersive faint page indicator (only when chrome hidden)
        if (hidden)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Center(
                child: PageNoIndicator(controller: app.viewer, isWide: false)),
          ),
        // top toolbar (slides up when hidden)
        Positioned(
          top: MediaQuery.of(context).padding.top + 10,
          left: 0,
          right: 0,
          child: IgnorePointer(
            ignoring: hidden,
            child: AnimatedSlide(
              offset: hidden ? const Offset(0, -2) : Offset.zero,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: hidden ? 0 : 1,
                duration: const Duration(milliseconds: 300),
                child: Center(
                    child: PageToolbar(controller: app.viewer, isWide: false)),
              ),
            ),
          ),
        ),
        // bottom chrome (chapter action + range card + mini bar) — slides down when hidden
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            ignoring: hidden,
            child: AnimatedSlide(
              offset: hidden ? const Offset(0, 1) : Offset.zero,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              child: AnimatedOpacity(
                opacity: hidden ? 0 : 1,
                duration: const Duration(milliseconds: 300),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (app.selectedChapter != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
                        child: ChapterActionBand(app: app),
                      ),
                    RangeStatusCard(app: app),
                    MiniBar(app: app),
                  ],
                ),
              ),
            ),
          ),
        ),
        // resume chip (fixed, bottom-center, above the chrome)
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.of(context).padding.bottom + 84,
          child: Center(child: ResumeChip(app: app)),
        ),
        // console sheet (cp-full, 62dvh)
        _consoleSheet(),
        // range selector sheet (70dvh)
        _rangeSheet(),
        // picker sheet (pause/speed/verse/section)
        PickerSheet(app: app),
        // full-screen verse search overlay
        SearchOverlay(app: app),
        // long-press verse menu (on top of everything)
        VerseMenu(app: app),
      ],
    );
  }

  Widget _viewerStack({required bool wide}) {
    return Stack(
      children: [
        Positioned.fill(child: PageViewer(controller: app.viewer)),
        if (wide)
          Positioned.fill(child: PageNavArrows(controller: app.viewer)),
        Positioned(
          top: 10,
          left: 0,
          right: 0,
          child: Center(child: PageToolbar(controller: app.viewer, isWide: wide)),
        ),
        Positioned(
          bottom: 10,
          left: 0,
          right: 0,
          child: Center(
              child: PageNoIndicator(controller: app.viewer, isWide: wide)),
        ),
      ],
    );
  }

  // ── console sheet (.cp-full mobile) ──
  Widget _consoleSheet() {
    final mq = MediaQuery.of(context);
    final h = mq.size.height * 0.62;
    final open = app.consoleExpanded;
    return Stack(
      children: [
        // backdrop (.cp-backdrop)
        IgnorePointer(
          ignoring: !open,
          child: GestureDetector(
            onTap: app.closeConsole,
            child: AnimatedOpacity(
              opacity: open ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: Container(color: const Color(0x73000000)),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: Duration(milliseconds: open ? 280 : 250),
          curve: open ? Curves.easeOut : Curves.easeIn,
          left: 0,
          right: 0,
          bottom: open ? 0 : -(h + 40),
          height: h,
          child: Transform.translate(
            offset: Offset(0, _consoleDrag),
            child: _sheetSurface(
              onDrag: (d) =>
                  setState(() => _consoleDrag = (_consoleDrag + d).clamp(0, 800)),
              onDragEnd: () {
                if (_consoleDrag > 80) app.closeConsole();
                setState(() => _consoleDrag = 0);
              },
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(16, 0, 16, mq.padding.bottom + 18),
                child: ConsoleBody(app: app, wide: false),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── range selector sheet (.rss-sheet, 70dvh) ──
  Widget _rangeSheet() {
    final mq = MediaQuery.of(context);
    final h = mq.size.height * 0.70;
    final open = app.rangeSheetOpen;
    return Stack(
      children: [
        IgnorePointer(
          ignoring: !open,
          child: GestureDetector(
            onTap: app.closeRangeSheet,
            child: AnimatedOpacity(
              opacity: open ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: Container(color: const Color(0x80000000)),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
          left: 0,
          right: 0,
          bottom: open ? 0 : -(h + 40),
          height: h,
          child: Transform.translate(
            offset: Offset(0, _rangeDrag),
            child: ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
              child: Container(
                color: C.ink2,
                child: Column(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onVerticalDragUpdate: (d) => setState(
                          () => _rangeDrag = (_rangeDrag + d.delta.dy).clamp(0, 800)),
                      onVerticalDragEnd: (_) {
                        if (_rangeDrag > 80) app.closeRangeSheet();
                        setState(() => _rangeDrag = 0);
                      },
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        child: Container(
                          width: 36,
                          height: 4,
                          decoration: BoxDecoration(
                            color: const Color(0x4DFFFFFF),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        child: RangeSelector(
                          app: app,
                          stickyTabs: true,
                          chapterScroll: ScrollController(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _sheetSurface({
    required Widget child,
    required ValueChanged<double> onDrag,
    required VoidCallback onDragEnd,
  }) {
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2E2110), Color(0xFF1F1609)],
          ),
          border: Border(top: BorderSide(color: C.goldDeep)),
        ),
        child: Column(
          children: [
            // sheet-grip
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) => onDrag(d.delta.dy),
              onVerticalDragEnd: (_) => onDragEnd(),
              child: Container(
                height: 40,
                color: const Color(0xFF2E2110),
                alignment: Alignment.center,
                padding: const EdgeInsets.only(top: 12),
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: C.muted2,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
            ),
            Expanded(child: child),
          ],
        ),
      ),
    );
  }
}
