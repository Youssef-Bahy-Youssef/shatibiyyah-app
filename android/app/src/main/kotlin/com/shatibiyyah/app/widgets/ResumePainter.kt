package com.shatibiyyah.app.widgets

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PorterDuff
import android.graphics.PorterDuffXfermode
import android.graphics.RectF
import android.text.TextPaint
import android.text.TextUtils
import com.shatibiyyah.app.R
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

/** One drawing of «تابع»: its size in dp and what it shows. */
internal class ResumeSpec(
    val width: Float,
    val height: Float,
    val state: ResumeState,
    val verse: WidgetVerse,
    val reciter: String?,
    /** The system's font scale: the two interface lines follow it as far as their row allows. */
    val fontScale: Float = 1f,
)

/**
 * «تابع» as drawn: one mask for each colour it is inked in. A mask holds coverage only (one byte a
 * pixel); the layout tints it. So the same drawing serves paper and night, and under «تلقائي» the
 * launcher itself picks the colours from the day or night resources.
 */
internal class ResumeLayers(
    /** onCover: the title, the verse, the number, and the disc or pill with its glyph cut out of it. */
    val ink: Bitmap,
    /** coverMute: the line under the title. */
    val mute: Bitmap,
    /** giltOnCover: the khatam, and the mark of the verse being recited. */
    val gilt: Bitmap,
    val metrics: ResumePainter.Metrics,
)

/**
 * Draws «تابع», the binding (ADR 0025; design/redesign/widgets.html): the dock's now-playing row
 * on the cover colour, a hairline, then the current verse, one hemistich to a line.
 *
 * It is drawn here, in dp, and not by the launcher's own text views, so the look is the design's
 * on every Android version: those cannot use the app's fonts before Android 8, and cannot centre,
 * size and lead a vocalised line the way the design does on any version.
 */
internal object ResumePainter {
    /** Where the layout puts things, in dp. The tap targets in the layout files follow it. */
    class Metrics(width: Float, val height: Float) {
        /** Under 150 dp of height the binding tightens its margins; nothing else changes. */
        val compact = height < 150f
        val padV = if (compact) 10f else 14f
        val padH = if (compact) 14f else 16f
        val row = if (compact) 44f else 48f
        val left = padH
        val right = width - padH
        val ruleY = padV + row + if (compact) 5f else 8f
        val bodyTop = ruleY + 1f + 2f
        val bodyBottom = height - padV
        val inner = width - 2 * padH
    }

    const val MAX_VERSE = 21f

    /** The tightest line the face takes with its tashkeel whole (the share card's dense layout). */
    const val MIN_LEADING = 1.68f

    /**
     * The verse size (ADR 0025): the largest half-pixel at which the poem's widest hemistich fits
     * one line, capped at 21. A widget too short for two such lines takes the size its height holds.
     */
    fun verseSize(m: Metrics, widestEm: Float): Float {
        val byWidth = floor((m.inner - 6f) / widestEm * 2f) / 2f
        val byHeight = floor((m.bodyBottom - m.bodyTop) / (2f * MIN_LEADING) * 2f) / 2f
        return max(1f, min(MAX_VERSE, min(byWidth, byHeight)))
    }

    /** Where the two lines of [verse] go: the size, the line height and the first line's top, in dp. */
    class VerseLayout(val size: Float, val lineHeight: Float, val top: Float, val paint: Paint)

    /**
     * Lays the verse out: at the widget's one size, the two lines centred under the hairline.
     *
     * A few verses carry marks taller than the line allows when the widget is short (a shadda
     * with a vowel over a tall letter reaches 1.4 em). So the lines are then placed by their own
     * ink: moved down until the first clears the hairline, and set smaller only if the second
     * would then come too near the edge. On a widget of the usual height nothing moves.
     */
    fun layout(context: Context, m: Metrics, verse: WidgetVerse): VerseLayout {
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = WidgetFonts.verse(context); color = MASK; textAlign = Paint.Align.CENTER; isSubpixelText = true
        }
        var size = verseSize(m, WidestHemistich.em(context))
        val room = m.bodyBottom - m.bodyTop
        val outline = Path()
        val ink = RectF()
        while (true) {
            paint.textSize = size
            // The size already holds the widest hemistich; this only guards a face that failed to load.
            val widest = max(paint.measureText(verse.first), paint.measureText(verse.second))
            val lineHeight = size * min(38f / 21f, max(MIN_LEADING, room / (2f * size)))
            var top = m.bodyTop + (room - 2f * lineHeight) / 2f
            paint.getTextPath(verse.first, 0, verse.first.length, 0f, 0f, outline)
            outline.computeBounds(ink, true)
            val rise = (m.ruleY + 1f + CLEAR) - (baseline(paint, top, lineHeight) + ink.top)
            if (rise > 0f) top += rise
            paint.getTextPath(verse.second, 0, verse.second.length, 0f, 0f, outline)
            outline.computeBounds(ink, true)
            val fits = widest <= m.inner && baseline(paint, top + lineHeight, lineHeight) + ink.bottom <= m.height - EDGE
            if (fits || size <= 1f) return VerseLayout(size, lineHeight, top, paint)
            size -= .5f
        }
    }

    /** What stays clear between a line's ink and the hairline above it, and the widget's edge below it, in dp. */
    private const val CLEAR = 1f
    private const val EDGE = 4f

    fun draw(context: Context, s: ResumeSpec, density: Float): ResumeLayers {
        val wPx = max(1, (s.width * density).roundToInt())
        val hPx = max(1, (s.height * density).roundToInt())
        val m = Metrics(s.width, s.height)
        fun layer(): Pair<Bitmap, Canvas> {
            val bitmap = Bitmap.createBitmap(wPx, hPx, Bitmap.Config.ALPHA_8)
            return bitmap to Canvas(bitmap).apply { scale(wPx / s.width, hPx / s.height) } // from here on every number is dp
        }
        val (ink, c) = layer()
        val (mute, cMute) = layer()
        val (gilt, cGilt) = layer()
        val fill = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = MASK }

        // The row: the khatam at the right, the one control at the left, the two lines between.
        val rowMid = m.padV + m.row / 2f
        khatam(context, cGilt, c, m.right - 22f, rowMid, 44f, arabicDigits(s.verse.number))

        val uiScale = min(s.fontScale, m.row / 36f)
        val controlWidth: Float
        if (s.state.audio) {
            c.drawCircle(m.left + 24f, rowMid, 24f, fill)
            icon(context, c, if (s.state.playing) R.drawable.widget_pause else R.drawable.widget_play, m.left + 24f, rowMid, 20f)
            controlWidth = 48f
        } else {
            controlWidth = pill(context, c, m.left, rowMid, uiScale)
        }

        val metaRight = m.right - 44f - 10f
        val metaWidth = metaRight - (m.left + controlWidth + 10f)
        val title = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = WidgetFonts.uiSemiBold(context); textSize = 14.5f * uiScale; color = MASK; textAlign = Paint.Align.RIGHT
        }
        val sub = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = WidgetFonts.ui(context); textSize = 12f * uiScale; color = MASK; textAlign = Paint.Align.RIGHT
        }
        val metaTop = rowMid - 18f * uiScale
        line(c, barTitle(s.verse.chapterLabel), title, metaRight, metaTop, 20f * uiScale, metaWidth)
        line(cMute, subtitle(s), sub, metaRight, metaTop + 20f * uiScale, 16f * uiScale, metaWidth)

        // Under the hairline (a view of the layout), the verse.
        val v = layout(context, m, s.verse)
        c.drawText(s.verse.first, s.width / 2f, baseline(v.paint, v.top, v.lineHeight), v.paint)
        c.drawText(s.verse.second, s.width / 2f, baseline(v.paint, v.top + v.lineHeight, v.lineHeight), v.paint)

        // Gilt marks the verse being recited, as in the margin of the reading screen.
        if (s.state.playing) cGilt.drawRoundRect(RectF(m.right + 4f, m.ruleY + 14f, m.right + 7f, m.bodyBottom - 10f), 2f, 2f, fill)
        return ResumeLayers(ink, mute, gilt, m)
    }

    /** The line under the title: «البيت N», then the reciter, or that the recitation is not on the device. */
    fun subtitle(s: ResumeSpec): String {
        val verse = "البيت ${arabicDigits(s.verse.number)}"
        return when {
            !s.state.audio -> "$verse · التلاوة غير منزّلة"
            s.reciter != null -> "$verse · ${s.reciter}"
            else -> verse
        }
    }

    /** What a screen reader says for the whole widget. */
    fun description(s: ResumeSpec): String =
        "${barTitle(s.verse.chapterLabel)}، ${subtitle(s).replace(" · ", "، ")}: ${s.verse.first} ${s.verse.second}"

    /** A baseline that centres the face's own ascent and descent in a line box, as CSS does. */
    fun baseline(paint: Paint, lineTop: Float, lineHeight: Float): Float {
        val fm = paint.fontMetrics
        return lineTop + (lineHeight - (fm.descent - fm.ascent)) / 2f - fm.ascent
    }

    /** One line ending in an ellipsis when it is too long, its right edge at [right]. */
    private fun line(c: Canvas, text: String, paint: TextPaint, right: Float, top: Float, lineHeight: Float, width: Float) {
        val shown = TextUtils.ellipsize(text, paint, max(0f, width), TextUtils.TruncateAt.END).toString()
        c.drawText(shown, right, baseline(paint, top, lineHeight), paint)
    }

    /** The eight-point star from two squares (v2.js `khatam`) on [star], and the number it holds on [number]. */
    private fun khatam(context: Context, star: Canvas, number: Canvas, cx: Float, cy: Float, size: Float, label: String) {
        val h = size * 0.335f
        val outer = h * sqrt(2f)
        val inner = (h / cos(PI / 8)).toFloat()
        val path = Path()
        for (k in 0 until 16) {
            val a = PI * k / 8 - PI / 2
            val r = if (k % 2 == 1) inner else outer
            val x = cx + (r * cos(a)).toFloat()
            val y = cy + (r * sin(a)).toFloat()
            if (k == 0) path.moveTo(x, y) else path.lineTo(x, y)
        }
        path.close()
        star.drawPath(path, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE; strokeWidth = 1.3f; strokeJoin = Paint.Join.ROUND; color = MASK
        })
        val fs = size * if (label.length > 2) 0.26f else if (label.length > 1) 0.3f else 0.34f
        number.drawText(label, cx, cy + fs * 0.36f, Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = WidgetFonts.uiSemiBold(context); textSize = fs; color = MASK; textAlign = Paint.Align.CENTER
        })
    }

    /** An icon of the app's set, [size] dp square and centred, cut out of what is drawn under it. */
    private fun icon(context: Context, c: Canvas, id: Int, cx: Float, cy: Float, size: Float) {
        val d = context.getDrawable(id)?.mutate() ?: return
        // Drawn in its own 24-unit box, so its bounds stay whole numbers under the dp scale.
        val box = RectF(cx - size / 2f, cy - size / 2f, cx + size / 2f, cy + size / 2f)
        c.saveLayer(box, CUT)
        c.translate(box.left, box.top)
        c.scale(size / 24f, size / 24f)
        d.setBounds(0, 0, 24, 24)
        d.draw(c)
        c.restore()
    }

    /** The dock's «تنزيل» pill, its arrow and word cut out of it; returns its width. */
    private fun pill(context: Context, c: Canvas, left: Float, midY: Float, scale: Float): Float {
        val label = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            typeface = WidgetFonts.uiSemiBold(context); textSize = 13f * scale; textAlign = Paint.Align.LEFT
            color = MASK; xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_OUT)
        }
        val text = "تنزيل"
        val width = 14f + label.measureText(text) + 6f + 18f + 14f
        c.drawRoundRect(RectF(left, midY - 18f, left + width, midY + 18f), 18f, 18f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = MASK })
        // Right to left: the arrow first, at the right; the word after it.
        icon(context, c, R.drawable.widget_download, left + width - 14f - 9f, midY, 18f)
        c.drawText(text, left + 14f, baseline(label, midY - 10f, 20f), label)
        return width
    }

    /** Full coverage: a mask keeps only how much of each pixel is inked. */
    private const val MASK = 0xFF000000.toInt()

    /** Removes what is drawn through it from what lies under it. */
    private val CUT = Paint().apply { xfermode = PorterDuffXfermode(PorterDuff.Mode.DST_OUT) }
}
