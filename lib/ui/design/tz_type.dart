// lib/ui/design/tz_type.dart — a type role at the reader's chosen text size.
import 'package:flutter/painting.dart';

extension TzTypeScale on TextStyle {
  /// This role, [factor] times its size (the text-size setting; the line height follows).
  TextStyle scaled(double factor) => copyWith(fontSize: fontSize! * factor);
}
