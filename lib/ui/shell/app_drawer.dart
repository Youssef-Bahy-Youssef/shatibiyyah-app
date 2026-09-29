// lib/ui/shell/app_drawer.dart — the ☰ drawer: the logo and name, then the
// destinations of the route table. 300 px on the start side (the right in RTL).
import 'package:flutter/material.dart';

import '../../app/routes.dart';
import '../../theme.dart' show kufi;
import '../design/taysir_colors.dart';
import '../design/taysir_logo.dart';
import '../reader/reader_controller.dart';

class AppDrawer extends StatelessWidget {
  final ReaderController reader;
  const AppDrawer({super.key, required this.reader});

  @override
  Widget build(BuildContext context) {
    final t = TaysirColors.of(context);
    return Drawer(
      width: 300,
      backgroundColor: t.panel,
      shape: Border(left: BorderSide(color: t.line)),
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 14),
              child: Row(
                children: [
                  const TaysirLogo(size: 48),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      'تيسير الشاطبية',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: kufi(size: 18, weight: 600, color: t.text),
                    ),
                  ),
                ],
              ),
            ),
            for (final route in AppRoute.values)
              InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  // Resolve the navigator before the drawer's own route goes away.
                  final navigator = Navigator.of(context);
                  navigator.pop();
                  navigator.push(MaterialPageRoute<void>(builder: (_) => route.build(reader)));
                },
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 50),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Row(
                      children: [
                        Icon(route.icon, size: 20, color: t.goldText),
                        const SizedBox(width: 14),
                        Flexible(
                          child: Text(
                            route.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: kufi(size: 15, weight: 400, color: t.text),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
