// lib/models/verse.dart — one entry of verses.json (1173 verses) and the derived
// per-verse box used everywhere by the data layer.
class Verse {
  final int id;
  final int page;
  final double x;
  final double y;
  final double width;
  final double height;

  const Verse({
    required this.id,
    required this.page,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
  });

  factory Verse.fromJson(Map<String, dynamic> j) => Verse(
        id: (j['id'] as num).toInt(),
        page: (j['page'] as num).toInt(),
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        width: (j['width'] as num).toDouble(),
        height: (j['height'] as num).toDouble(),
      );
}

/// ported from data.js: verseMap value — { page, x, y, w, h, chapterId }.
class Box {
  final int page;
  final double x;
  final double y;
  final double w;
  final double h;
  final int chapterId;
  const Box(this.page, this.x, this.y, this.w, this.h, this.chapterId);
}
