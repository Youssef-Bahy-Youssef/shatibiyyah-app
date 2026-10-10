// lib/models/chapter.dart — one entry of chapters.json (79 chapters).
// Shape: { name, start_verse, end_verse, verse_count, start_time, header_text?,
//          x?, y?, width?, height? }  — header geometry (x/width) is optional.
class Chapter {
  final String name;
  final int startVerse;
  final int endVerse;
  final int verseCount;
  final double? startTime;
  final String? headerText;

  /// The page its heading is printed on (null when it has none, like الخاتمة).
  final int? page;
  final double? x;
  final double? y;
  final double? width;
  final double? height;

  const Chapter({
    required this.name,
    required this.startVerse,
    required this.endVerse,
    required this.verseCount,
    required this.startTime,
    this.headerText,
    this.page,
    this.x,
    this.y,
    this.width,
    this.height,
  });

  factory Chapter.fromJson(Map<String, dynamic> j) => Chapter(
        name: j['name'] as String,
        startVerse: (j['start_verse'] as num).toInt(),
        endVerse: (j['end_verse'] as num).toInt(),
        verseCount: (j['verse_count'] as num?)?.toInt() ??
            ((j['end_verse'] as num).toInt() -
                (j['start_verse'] as num).toInt() +
                1),
        startTime: (j['start_time'] as num?)?.toDouble(),
        headerText: j['header_text'] as String?,
        page: (j['page'] as num?)?.toInt(),
        x: (j['x'] as num?)?.toDouble(),
        y: (j['y'] as num?)?.toDouble(),
        width: (j['width'] as num?)?.toDouble(),
        height: (j['height'] as num?)?.toDouble(),
      );
}
