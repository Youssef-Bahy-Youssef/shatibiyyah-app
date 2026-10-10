// lib/ui/design/night_page.dart — a scan of the matn drawn as the night page
// (ADR 0020): through the chosen ink's colour matrix.
import 'tokens.g.dart';

/// [ink]'s 4×5 matrix for ColorFilter.matrix, its colour rows scaled by
/// [brightness]. The tokens hold an SVG feColorMatrix, whose offset column is on
/// a 0…1 scale; Flutter's is on 0…255.
List<double> nightInkMatrix(TzNightInk ink, {double brightness = 1}) => [
      for (var i = 0; i < 20; i++) ink.matrix[i] * (i % 5 == 4 ? 255 : 1) * (i < 15 ? brightness : 1),
    ];
