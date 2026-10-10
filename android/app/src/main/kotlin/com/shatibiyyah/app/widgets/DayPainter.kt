package com.shatibiyyah.app.widgets

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.text.TextPaint
import android.text.TextUtils
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

/** One drawing of «بيت اليوم»: its size in dp, the verse, and whether names and symbols take the rubric ink. */
internal class DaySpec(val width: Float, val height: Float, val verse: WidgetVerse, val rubric: Boolean)

/** A mask over the rows it inks only, from [top] to [bottom] in dp: most of a widget is not inked in any one colour. */
internal class Band(val bitmap: Bitmap, val top: Float, val bottom: Float)

/** «بيت اليوم» as drawn: one mask for each colour it is inked in (see [ResumeLayers]). */
internal class DayLayers(
    /** verseInk: the verse. */
    val verse: Band,
    /** rubric: reader names and symbols, and a symbol's dotted underline. */
    val rubric: Band,
    /** ink2: the chapter's title. */
    val chapter: Band,
    /** ink: the verse's number. */
    val number: Band,
    /** gilt: the khatam, and the rule it sits on at 55%. */
    val gilt: Band,
    val metrics: DayPainter.Metrics,
)

/**
 * Draws «بيت اليوم», the leaf (ADR 0025; design/redesign/widgets.html): the matn strip. A gilt
 * rule carries the khatam; under it the verse is laid out as in the text view; the chapter's title
 * sits on a second rule.
 *
 * At four cells wide the first hemistich starts at the right and the second ends at the left,
 * each on one line, justified when it fills most of its column. Narrower than that, each
 * hemistich is centred and may wrap inside itself to two balanced lines, never across the two.
 */
internal object DayPainter {
    class Metrics(val width: Float, val height: Float) {
        /** The 2×2 form: narrower than four cells. */
        val stacked = width < 250f
        val padH = if (stacked) 12f else 16f
        val padTop = if (stacked) 10f else 12f
        val padBottom = if (stacked) 8f else 10f

        /** The ornament row's height, which is also the khatam's size. */
        val orn = if (stacked) 24f else 30f
        val chapterSize = if (stacked) 13.5f else 15f
        val chapterLine = if (stacked) 18f else 22f
        val left = padH
        val right = width - padH
        val inner = width - 2 * padH
        val chapterTop = height - padBottom - chapterLine

        /** The rule the chapter's title sits on. */
        val ruleY = chapterTop - (if (stacked) 2f else 3f) - 1f
        val bodyTop = padTop + orn
        val bodyBottom = ruleY - (if (stacked) 5f else 3f)

        /** A hemistich's column: 93% of the width where the two are set against opposite edges. */
        val column = if (stacked) inner else inner * .93f
    }

    /** One drawn line: a range of a hemistich's text and its natural width. */
    class Line(val hemistich: Int, val start: Int, val end: Int, val width: Float)

    /** The verse laid out: the size, the line height, the first line's top, and the lines in order. */
    class VerseLayout(val size: Float, val lineHeight: Float, val top: Float, val lines: List<Line>, val paint: Paint)

    const val MAX_VERSE = 21f
    const val MAX_STACKED = 17f
    private const val LEADING = ResumePainter.MIN_LEADING
    private const val MAX_LEADING = 1.95f

    /** The air between the two hemistichs in the 2×2 form. */
    private const val BETWEEN = 4f

    /** A hemistich is justified only when it fills this much of its column; a shorter one stays ragged. */
    private const val JUSTIFY_FROM = .84f

    /** A symbol's underline: its distance under the baseline in em, its thickness in dp. */
    private const val UNDER_OFFSET = .32f
    private const val UNDER_WIDTH = 1.5f

    private fun half(x: Float) = floor(x * 2f) / 2f

    /** A line measured at [REF] px: its range, its width, and how far its ink reaches above and below the baseline. */
    private class Measured(val hemistich: Int, val start: Int, val end: Int, val width: Float, val inkTop: Float, val inkBottom: Float) {
        fun at(size: Float) = Line(hemistich, start, end, width * size / REF)
    }

    /** A hemistich measured once: whole, and as its two most even lines (null if it is one word). */
    private class Hemistich(val whole: Measured, val halves: Pair<Measured, Measured>?)

    private const val REF = 100f

    /**
     * Lays the verse out. Everything is measured once, at one size: a line's width and its ink
     * grow with the size in proportion, and so the most even way to break a hemistich in two is
     * the same at every size. Finding the size is then arithmetic.
     */
    fun layout(context: Context, m: Metrics, verse: WidgetVerse): VerseLayout {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = WidgetFonts.verse(context); color = MASK; isSubpixelText = true; textSize = REF }
        val room = m.bodyBottom - m.bodyTop
        val measured = listOf(verse.first, verse.second).mapIndexed { i, text -> measure(text, i + 1, paint, split = m.stacked) }
        val between = if (m.stacked) BETWEEN else 0f
        var size = if (m.stacked) MAX_STACKED else min(MAX_VERSE, half((m.column - 4f) / WidestHemistich.em(context)))
        while (true) {
            val k = size / REF
            var fits = true
            // One line where it fits (always, at four cells wide); else its two most even lines.
            val lines = measured.flatMap { h ->
                val halves = h.halves
                if (!m.stacked || h.whole.width * k <= m.column || halves == null) listOf(h.whole) else listOf(halves.first, halves.second)
            }
            if (lines.any { it.width * k > m.column + .5f }) fits = false
            val lineHeight = size * min(MAX_LEADING, max(LEADING, (room - between) / (lines.size * size)))
            if (lines.size * size * LEADING + between > room + .5f) fits = false
            var top = m.bodyTop + (room - between - lines.size * lineHeight) / 2f
            // By its own ink (see ResumePainter.layout): clear of the ornament above and of the rule
            // below. Lines that reach one of them move away from it, if the other side has the room;
            // only lines that reach both are set smaller.
            paint.textSize = size
            val first = lines.first()
            val last = lines.last()
            var inkBottom = last.inkBottom * k
            if (verse.marks.any { it.symbol && it.hemistich == last.hemistich && it.end > last.start && it.start < last.end }) {
                inkBottom = max(inkBottom, UNDER_OFFSET * size + UNDER_WIDTH)
            }
            fun rise(top: Float) = (m.bodyTop - 1f) - (baseline(paint, top, lineHeight) + first.inkTop * k)
            fun sink(top: Float) = baseline(paint, top + (lines.size - 1) * lineHeight + between, lineHeight) + inkBottom - (m.ruleY - 1f)
            if (rise(top) > 0f) top += rise(top) else if (sink(top) > 0f) top -= sink(top)
            if (rise(top) > .01f || sink(top) > .01f) fits = false
            if (fits || size <= 6f) return VerseLayout(size, lineHeight, top, lines.map { it.at(size) }, paint)
            size -= .5f
        }
    }

    private val outline = Path()
    private val inkBox = RectF()

    @Synchronized
    private fun measured(text: String, hemistich: Int, start: Int, end: Int, paint: Paint): Measured {
        paint.getTextPath(text, start, end, 0f, 0f, outline)
        outline.computeBounds(inkBox, true)
        return Measured(hemistich, start, end, lineWidth(text, start, end, paint), inkBox.top, inkBox.bottom)
    }

    private fun measure(text: String, hemistich: Int, paint: Paint, split: Boolean): Hemistich {
        val whole = measured(text, hemistich, 0, text.length, paint)
        val w = words(text, 0, text.length)
        if (!split || w.size < 2) return Hemistich(whole, null)
        // The break that leaves the narrower of the two widest lines.
        var best = 1
        var bestWidest = Float.MAX_VALUE
        for (k in 1 until w.size) {
            val widest = max(lineWidth(text, w.first().first, w[k - 1].last + 1, paint), lineWidth(text, w[k].first, w.last().last + 1, paint))
            if (widest < bestWidest) {
                bestWidest = widest
                best = k
            }
        }
        return Hemistich(whole, measured(text, hemistich, w.first().first, w[best - 1].last + 1, paint) to measured(text, hemistich, w[best].first, w.last().last + 1, paint))
    }

    /** The words of [text] between [start] and [end]: their ranges. */
    private fun words(text: String, start: Int, end: Int): List<IntRange> {
        val out = ArrayList<IntRange>()
        var i = start
        while (i < end) {
            while (i < end && text[i] == ' ') i++
            var j = i
            while (j < end && text[j] != ' ') j++
            if (j > i) out.add(i until j)
            i = j
        }
        return out
    }

    private fun advance(text: String, range: IntRange, paint: Paint): Float =
        paint.getRunAdvance(text, range.first, range.last + 1, range.first, range.last + 1, true, range.last + 1)

    private fun lineWidth(text: String, start: Int, end: Int, paint: Paint): Float {
        val w = words(text, start, end)
        return w.sumOf { advance(text, it, paint).toDouble() }.toFloat() + max(0, w.size - 1) * paint.measureText(" ")
    }

    fun draw(context: Context, s: DaySpec, density: Float): DayLayers {
        val m = Metrics(s.width, s.height)
        val wPx = max(1, (s.width * density).roundToInt())
        fun band(top: Float, bottom: Float): Pair<Band, Canvas> {
            val topPx = (top * density).roundToInt()
            val hPx = max(1, (bottom * density).roundToInt() - topPx)
            val bitmap = Bitmap.createBitmap(wPx, hPx, Bitmap.Config.ALPHA_8)
            // Every number drawn is dp, counted from the widget's own top.
            val canvas = Canvas(bitmap).apply { translate(0f, -topPx.toFloat()); scale(wPx / s.width, density) }
            return Band(bitmap, top, bottom) to canvas
        }
        // The ornament row; the verse, from just above its first line to the rule; the title under the rule.
        val (gilt, cGilt) = band(0f, m.bodyTop)
        val (number, cNumber) = band(0f, m.bodyTop)
        val (verse, cVerse) = band(m.bodyTop - 3f, m.ruleY)
        val (rubric, cRubric) = band(m.bodyTop - 3f, m.ruleY)
        val (chapter, cChapter) = band(m.ruleY + 1f, min(s.height, m.chapterTop + m.chapterLine + 6f))

        // The khatam on its rule.
        val mid = m.padTop + m.orn / 2f
        val rule = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = MASK; alpha = (255 * RULE_ALPHA).roundToInt() }
        cGilt.drawRect(m.left, mid - .5f, s.width / 2f - m.orn / 2f - 8f, mid + .5f, rule)
        cGilt.drawRect(s.width / 2f + m.orn / 2f + 8f, mid - .5f, m.right, mid + .5f, rule)
        ResumePainter.khatam(context, cGilt, cNumber, s.width / 2f, mid, m.orn, arabicDigits(s.verse.number))

        // The verse.
        val v = layout(context, m, s.verse)
        val texts = listOf(s.verse.first, s.verse.second)
        var top = v.top
        for ((i, line) in v.lines.withIndex()) {
            if (m.stacked && i > 0 && line.hemistich != v.lines[i - 1].hemistich) top += BETWEEN
            val marks = if (s.rubric) s.verse.marks.filter { it.hemistich == line.hemistich } else emptyList()
            val justified = !m.stacked && line.width >= m.column * JUSTIFY_FROM
            // Where the line's right edge is, and how wide it is drawn.
            val (right, width) = when {
                m.stacked -> (s.width + line.width) / 2f to line.width
                line.hemistich == 1 -> m.right to (if (justified) m.column else line.width)
                else -> (m.left + if (justified) m.column else line.width) to (if (justified) m.column else line.width)
            }
            line(cVerse, cRubric, texts[line.hemistich - 1], line, marks, right, width, baseline(v.paint, top, v.lineHeight), v.paint)
            top += v.lineHeight
        }

        // The chapter's title, on its rule (the rule itself is a view of the layout).
        val title = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = WidgetFonts.chapter(context); textSize = m.chapterSize; color = MASK; textAlign = Paint.Align.CENTER
        }
        val shown = TextUtils.ellipsize(s.verse.chapterTitle, title, m.inner, TextUtils.TruncateAt.END).toString()
        cChapter.drawText(shown, s.width / 2f, baseline(title, m.chapterTop, m.chapterLine), title)
        return DayLayers(verse, rubric, chapter, number, gilt, m)
    }

    /**
     * Draws one line right to left, its right edge at [right], spread over [width]. A mark's letters
     * go to [cRubric], the rest to [cVerse]. Each word is shaped whole and drawn in pieces, so a
     * letter that takes the rubric ink stays joined to the rest of its word.
     */
    private fun line(cVerse: Canvas, cRubric: Canvas, text: String, line: Line, marks: List<WidgetMark>, right: Float, width: Float, baseline: Float, paint: Paint) {
        val words = words(text, line.start, line.end)
        val space = paint.measureText(" ") + if (words.size > 1) (width - line.width) / (words.size - 1) else 0f
        val under = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = MASK; style = Paint.Style.STROKE; strokeWidth = UNDER_WIDTH; strokeCap = Paint.Cap.ROUND
            pathEffect = DashPathEffect(floatArrayOf(.01f, UNDER_WIDTH * 2f), 0f)
        }
        var x = right
        for (word in words) {
            val wordEnd = word.last + 1
            // The word cut where a mark starts or ends inside it.
            val cuts = sortedSetOf(word.first, wordEnd)
            for (mark in marks) {
                if (mark.start in (word.first + 1) until wordEnd) cuts.add(mark.start)
                if (mark.end in (word.first + 1) until wordEnd) cuts.add(mark.end)
            }
            val edges = cuts.toList()
            for (k in 0 until edges.size - 1) {
                val from = edges[k]
                val to = edges[k + 1]
                val advance = paint.getRunAdvance(text, from, to, word.first, wordEnd, true, to)
                val mark = marks.firstOrNull { it.start <= from && it.end >= to }
                val canvas = if (mark != null) cRubric else cVerse
                canvas.drawTextRun(text, from, to, word.first, wordEnd, x - advance, baseline, true, paint)
                if (mark != null && mark.symbol && advance > 0f) {
                    val y = baseline + UNDER_OFFSET * paint.textSize + UNDER_WIDTH / 2f
                    cRubric.drawLine(x - advance + UNDER_WIDTH / 2f, y, x - UNDER_WIDTH / 2f, y, under)
                }
                x -= advance
            }
            x -= space
        }
    }

    private fun baseline(paint: Paint, lineTop: Float, lineHeight: Float) = ResumePainter.baseline(paint, lineTop, lineHeight)

    /** What a screen reader says for the whole widget. */
    fun description(s: DaySpec): String =
        "بيت اليوم: البيت ${arabicDigits(s.verse.number)}، ${plainName(s.verse.chapterTitle)}: ${s.verse.first} ${s.verse.second}"

    /** The share of gilt the rules are drawn in (the ornament rule of tokens.json: 55%). */
    const val RULE_ALPHA = .55f

    private const val MASK = 0xFF000000.toInt()
}
