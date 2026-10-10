// lib/ui/design/components/tz_motion.dart — motion that honours reduced motion.
//
// Every component animates with the token durations and curves (tokens.json
// motion) and is instant when the platform asks for reduced motion
// (MediaQuery.disableAnimations), as the spec says: "everything instant".
import 'package:flutter/widgets.dart';

/// [d], or zero under reduced motion.
Duration tzDuration(BuildContext context, Duration d) =>
    MediaQuery.maybeDisableAnimationsOf(context) == true ? Duration.zero : d;
