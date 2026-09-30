// lib/data/benefits_repository.dart — «فائدة اليوم» (G-19): the Al-Wafi passages
// the pipeline typed `summary` (the book's «الخلاصة») or `benefit` («فائدة»), with
// their verses, in the poem's order. One is shown per day, in rotation. No
// schema change: the rows are commentary_segments of the snapshot.
import 'package:sqflite/sqflite.dart';

/// The book the benefits come from.
const String kBenefitsCommentaryId = 'commentary:shatibiyyah:al-wafi';

enum BenefitKind { summary, benefit }

class DailyBenefit {
  final BenefitKind kind;
  final int fromVerse;
  final int toVerse;
  final String text; // the segment's display text
  const DailyBenefit(this.kind, this.fromVerse, this.toVerse, this.text);
}

class BenefitsRepository {
  final List<DailyBenefit> all;
  const BenefitsRepository(this.all);

  static Future<BenefitsRepository> load(Database db) async => BenefitsRepository([
    for (final r in await db.rawQuery(
      'SELECT s.segment_type AS kind, b.from_verse AS from_verse, b.to_verse AS to_verse, '
      's.display_text AS text '
      'FROM commentary_segments s JOIN commentary_blocks b ON b.id = s.commentary_block_id '
      "WHERE b.commentary_id = ? AND s.segment_type IN ('summary', 'benefit') AND b.from_verse IS NOT NULL "
      "AND trim(s.display_text) != '' "
      'ORDER BY b.from_verse, b.source_order, s.order_index',
      [kBenefitsCommentaryId],
    ))
      DailyBenefit(
        r['kind'] == 'benefit' ? BenefitKind.benefit : BenefitKind.summary,
        r['from_verse'] as int,
        (r['to_verse'] as int?) ?? r['from_verse'] as int,
        (r['text'] as String).trim(),
      ),
  ]);

  /// The benefit of the calendar day of [day]: the list in turn, one per day,
  /// the same on every device on the same date.
  DailyBenefit? forDay(DateTime day) => all.isEmpty ? null : all[dayNumber(day) % all.length];
}

/// Days from 1 January 2026 to the calendar date of [d] (its local date, not its instant).
int dayNumber(DateTime d) => DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(2026)).inDays;
