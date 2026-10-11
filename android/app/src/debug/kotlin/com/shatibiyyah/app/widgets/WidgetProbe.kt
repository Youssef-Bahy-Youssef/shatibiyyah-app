package com.shatibiyyah.app.widgets

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import kotlin.concurrent.thread

/**
 * Debug builds only: checks the widgets' drawing on a real Android, where their text is shaped
 * and measured (tool/widget_check.sh runs it and reads the result).
 *
 *     adb shell am broadcast -n <package>/com.shatibiyyah.app.widgets.WidgetProbe
 *
 * For every verse of the poem, at each size and font scale, it checks that both hemistichs fit
 * their line and that their ink stays between the hairline and the widget's edge. It then draws
 * the states of the design (design/redesign/widgets/) as PNG files, to set beside its renders.
 * It first redraws the widgets that are on the home screen. The result is
 * files/widget-probe/report.json in the app's external files.
 */
class WidgetProbe : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        val days = intent.getStringExtra("days")
        // The placed widgets are drawn again first, as after a change of state («--es only redraw» stops there).
        ResumeWidget.redrawAll(app)
        app.sendBroadcast(Intent(app, DayWidget::class.java).setAction(DayWidget.ACTION_MIDNIGHT))
        if (intent.getStringExtra("only") == "redraw") return
        // The broadcast stays open for the checks, so the process is not put to sleep in the middle of them.
        val pending = goAsync()
        thread {
            try {
                run(app, days)
            } finally {
                pending.finish()
            }
        }
    }

    private fun run(context: Context, days: String?) {
        val started = System.currentTimeMillis()
        val out = File(context.getExternalFilesDir(null), "widget-probe").apply { deleteRecursively(); mkdirs() }
        val report = JSONObject()
        try {
            val density = context.resources.displayMetrics.density
            val em = WidestHemistich.em(context)
            report.put("density", density.toDouble()).put("widestEm", em.toDouble())
            val verses = (1..1173).mapNotNull { WidgetContent.verse(context, it) }
            report.put("verses", verses.size)

            val forms = JSONArray()
            for ((w, h) in SIZES) {
                val m = ResumePainter.Metrics(w, h)
                var bad = 0
                var firstBad = ""
                val sizes = sortedMapOf<Float, Int>()
                var moved = 0
                var widestShare = 0f
                // The ink itself, from the glyphs' outlines: getTextBounds rounds out to whole units.
                val outline = Path()
                val ink = RectF()
                for (v in verses) {
                    val l = ResumePainter.layout(context, m, v)
                    sizes[l.size] = (sizes[l.size] ?: 0) + 1
                    if (l.top > m.bodyTop + (m.bodyBottom - m.bodyTop - 2f * l.lineHeight) / 2f + 0.01f) moved++
                    var ok = 2f * l.lineHeight <= m.bodyBottom - m.bodyTop + 0.01f
                    for ((i, text) in listOf(v.first, v.second).withIndex()) {
                        val width = l.paint.measureText(text)
                        widestShare = maxOf(widestShare, width / m.inner)
                        l.paint.getTextPath(text, 0, text.length, 0f, 0f, outline)
                        outline.computeBounds(ink, true)
                        val base = ResumePainter.baseline(l.paint, l.top + i * l.lineHeight, l.lineHeight)
                        // In its line's width; under the hairline; and inside the widget, clear of its bottom edge.
                        val why = when {
                            width > m.inner -> "wider than its line by ${width - m.inner}"
                            base + ink.top < m.ruleY + 1f -> "line ${i + 1} rises ${m.ruleY + 1f - (base + ink.top)} over the hairline"
                            base + ink.bottom > h - 2f -> "line ${i + 1} ends ${base + ink.bottom - (h - 2f)} past the edge"
                            else -> null
                        }
                        if (why != null) {
                            ok = false
                            if (firstBad.isEmpty()) firstBad = "verse ${v.number}: $why (size ${l.size}, line ${l.lineHeight}, ascent ${l.paint.fontMetrics.ascent}, descent ${l.paint.fontMetrics.descent})"
                        }
                    }
                    if (!ok) bad++
                }
                forms.put(JSONObject().put("size", "${w.toInt()}x${h.toInt()}").put("verseSizes", sizes.toString()).put("movedDown", moved)
                    .put("widestLineShare", widestShare.toDouble()).put("bad", bad).put("firstBad", firstBad))
            }
            report.put("forms", forms)

            // The design's states, drawn here.
            val widest = verses.maxByOrNull { v ->
                val p = ResumePainter.layout(context, ResumePainter.Metrics(340f, 180f), v).paint
                maxOf(p.measureText(v.first), p.measureText(v.second))
            }!!
            report.put("widestVerse", widest.number)
            val main = verses[225]
            val reciter = WidgetContent.reciter(context, DEFAULT_RECORDING) ?: "?"
            report.put("reciter", reciter).put("chapter", barTitle(main.chapterLabel))
            fun shot(name: String, w: Float, h: Float, v: WidgetVerse, playing: Boolean, audio: Boolean, scale: Float = 1f) {
                val state = ResumeState(verse = v.number, playing = playing, audio = audio, recording = DEFAULT_RECORDING)
                // 2×, as the design's renders are.
                val layers = ResumePainter.draw(context, ResumeSpec(w, h, state, v, if (audio) reciter else null, scale), 2f)
                for (night in listOf(false, true)) {
                    val bitmap = flatten(layers, if (night) WidgetTokens.night else WidgetTokens.paper, 2f)
                    File(out, "$name-${if (night) "night" else "paper"}.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
                }
            }
            shot("resume-playing", 340f, 180f, main, playing = true, audio = true)
            shot("resume-paused", 340f, 180f, main, playing = false, audio = true)
            shot("resume-none", 340f, 180f, main, playing = false, audio = false)
            shot("resume-fresh", 340f, 180f, verses[0], playing = false, audio = false)
            shot("resume-longest", 340f, 180f, widest, playing = false, audio = true)
            shot("size-resume-min", 276f, 130f, widest, playing = true, audio = true)
            shot("size-resume-tall", 360f, 220f, main, playing = false, audio = true)
            shot("size-resume-cells", 250f, 110f, widest, playing = true, audio = true)
            shot("scale-resume-200", 340f, 180f, main, playing = false, audio = true, scale = 2f)

            day(context, out, report, verses, widest, days)

            // The widgets on the home screen now: the sizes the launcher gives them, and what one drawing weighs.
            val manager = AppWidgetManager.getInstance(context)
            val placed = JSONArray()
            for (id in manager.getAppWidgetIds(ComponentName(context, ResumeWidget::class.java))) {
                val sizes = ResumeWidget.sizes(manager.getAppWidgetOptions(id))
                val bytes = sizes.sumOf { 3L * Math.round(it.width * density) * Math.round(it.height * density) }
                placed.put(JSONObject().put("widget", "resume").put("id", id).put("sizesDp", sizes.joinToString { "${it.width}x${it.height}" }).put("maskBytes", bytes))
            }
            val today = DailyVerse.today()
            for (id in manager.getAppWidgetIds(ComponentName(context, DayWidget::class.java))) {
                val sizes = ResumeWidget.sizes(manager.getAppWidgetOptions(id))
                val number = DayWidget.verseFor(context, id, today, verses.size)
                val bytes = sizes.sumOf { size ->
                    val l = DayPainter.draw(context, DaySpec(size.width, size.height, verses[number - 1], true), density)
                    // The rubric mask is sent once though two views show it.
                    listOf(l.verse, l.rubric, l.chapter, l.number, l.gilt).sumOf { it.bitmap.allocationByteCount.toLong() }
                }
                placed.put(JSONObject().put("widget", "day").put("id", id).put("sizesDp", sizes.joinToString { "${it.width}x${it.height}" })
                    .put("maskBytes", bytes).put("added", WidgetStore.dayAdded(context, id)).put("today", today).put("verse", number))
            }
            val screen = context.resources.displayMetrics
            report.put("placed", placed).put("bitmapLimitBytes", 6L * screen.widthPixels * screen.heightPixels)
            report.put("ok", true)
        } catch (e: Exception) {
            report.put("ok", false).put("error", e.toString())
        }
        report.put("seconds", (System.currentTimeMillis() - started) / 1000.0)
        File(out, "report.json").writeText(report.toString(2))
    }

    /** «بيت اليوم»: every verse in every form, the day arithmetic's cases, and the design's states. */
    private fun day(context: Context, out: File, report: JSONObject, verses: List<WidgetVerse>, widest: WidgetVerse, days: String?) {
        val forms = JSONArray()
        for ((w, h) in DAY_SIZES) {
            val m = DayPainter.Metrics(w, h)
            val sizes = sortedMapOf<Float, Int>()
            var bad = 0
            var firstBad = ""
            val outline = Path()
            val ink = RectF()
            for (v in verses) {
                val l = DayPainter.layout(context, m, v)
                sizes[l.size] = (sizes[l.size] ?: 0) + 1
                val texts = listOf(v.first, v.second)
                var why: String? = null
                // Every word of both hemistichs is on a line, in order.
                for (h12 in 1..2) {
                    val mine = l.lines.filter { it.hemistich == h12 }
                    if (mine.isEmpty() || mine.size > (if (m.stacked) 2 else 1)) why = "hemistich $h12 on ${mine.size} lines"
                    val drawn = mine.joinToString(" ") { texts[h12 - 1].substring(it.start, it.end).trim() }.replace(Regex(" +"), " ")
                    if (drawn != texts[h12 - 1].trim().replace(Regex(" +"), " ")) why = "hemistich $h12 lost text"
                }
                var top = l.top
                for ((i, line) in l.lines.withIndex()) {
                    if (m.stacked && i > 0 && line.hemistich != l.lines[i - 1].hemistich) top += 4f
                    val text = texts[line.hemistich - 1]
                    l.paint.getTextPath(text, line.start, line.end, 0f, 0f, outline)
                    outline.computeBounds(ink, true)
                    val base = ResumePainter.baseline(l.paint, top, l.lineHeight)
                    if (line.width > m.column + .5f) why = "a line wider than its column by ${line.width - m.column}"
                    if (i == 0 && base + ink.top < m.bodyTop - 1.01f) why = "the first line rises ${m.bodyTop - 1f - (base + ink.top)} into the ornament"
                    if (i == l.lines.size - 1 && base + ink.bottom > m.ruleY - .99f) why = "the last line ends ${base + ink.bottom - (m.ruleY - 1f)} past the rule"
                    top += l.lineHeight
                }
                if (l.lines.size * l.lineHeight + (if (m.stacked) 4f else 0f) > m.bodyBottom - m.bodyTop + .5f && l.size > 6f) why = "the lines are taller than their room"
                if (why != null) {
                    bad++
                    if (firstBad.isEmpty()) firstBad = "verse ${v.number}: $why (size ${l.size})"
                }
            }
            forms.put(JSONObject().put("size", "${w.toInt()}x${h.toInt()}").put("form", if (m.stacked) "2x2" else "4x2")
                .put("verseSizes", sizes.toString()).put("bad", bad).put("firstBad", firstBad))
        }
        report.put("dayForms", forms)

        // The day arithmetic, on the cases of test/fixtures/daily_verse.json («added,today,verse/…»).
        val wrong = JSONArray()
        var checked = 0
        for (case in (days ?: "").split("/").filter { it.isNotBlank() }) {
            val (added, today, verse) = case.split(",")
            checked++
            val got = DailyVerse.verse(added, today, verses.size)
            if (got != verse.toInt()) wrong.put("$added → $today: $got, not $verse")
        }
        report.put("dayCases", checked).put("dayCasesWrong", wrong)

        val short = verses.minByOrNull { v ->
            val p = DayPainter.layout(context, DayPainter.Metrics(340f, 180f), v).paint
            maxOf(p.measureText(v.first), p.measureText(v.second))
        }!!
        report.put("narrowestVerse", short.number)
        fun shot(name: String, w: Float, h: Float, v: WidgetVerse) {
            val layers = DayPainter.draw(context, DaySpec(w, h, v, true), 2f)
            for (night in listOf(false, true)) {
                val bitmap = flattenDay(layers, if (night) WidgetTokens.night else WidgetTokens.paper, night, 2f)
                File(out, "$name-${if (night) "night" else "paper"}.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
            }
        }
        val main = verses[225]
        val symbols = verses[1026]
        shot("day-short", 340f, 180f, short)
        shot("day-longest", 340f, 180f, widest)
        shot("day-symbols", 340f, 180f, symbols)
        shot("day-names", 340f, 180f, main)
        shot("day-sq-short", 160f, 180f, short)
        shot("day-sq-longest", 160f, 180f, widest)
        shot("day-sq-symbols", 160f, 180f, symbols)
        shot("size-day-min", 276f, 130f, widest)
        shot("size-day-sq-min", 140f, 160f, widest)
        shot("size-day-sq-tall", 170f, 210f, symbols)
        shot("size-day-tall", 360f, 220f, symbols)
        shot("size-day-cells", 110f, 110f, widest)
    }

    /** The leaf as the layout shows it: the vellum, the rule, then each band's mask in its colour. */
    private fun flattenDay(layers: DayLayers, colors: WidgetColors, night: Boolean, scale: Float): Bitmap {
        val m = layers.metrics
        val w = layers.verse.bitmap.width
        val h = Math.round(m.height * scale)
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val r = WidgetTokens.radiusDock * scale
        paint.color = colors.matnBg
        c.drawRoundRect(0f, 0f, w.toFloat(), h.toFloat(), r, r, paint)
        if (night) {
            paint.style = Paint.Style.STROKE; paint.strokeWidth = scale; paint.color = colors.lineSoft
            c.drawRoundRect(scale / 2, scale / 2, w - scale / 2, h - scale / 2, r - scale / 2, r - scale / 2, paint)
            paint.style = Paint.Style.FILL
        }
        paint.color = colors.gilt
        paint.alpha = Math.round(255 * DayPainter.RULE_ALPHA)
        c.drawRect(m.left * scale, m.ruleY * scale, m.right * scale, (m.ruleY + 1f) * scale, paint)
        val rubric = if (night) WidgetTokens.nightInks.getValue(WidgetTokens.defaultNightInk) else colors.rubric
        for ((band, color) in listOf(layers.gilt to colors.gilt, layers.number to colors.ink, layers.chapter to colors.ink2,
            layers.verse to colors.verseInk, layers.rubric to rubric)) {
            paint.color = color
            c.drawBitmap(band.bitmap, 0f, Math.round(band.top * scale).toFloat(), paint)
        }
        return out
    }

    /** The layers as the layout shows them: the cover, the ring, the hairline, then each mask in its colour. */
    private fun flatten(layers: ResumeLayers, colors: WidgetColors, scale: Float): Bitmap {
        val w = layers.ink.width
        val h = layers.ink.height
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)
        val r = WidgetTokens.radiusDock * scale
        paint.color = colors.cover
        c.drawRoundRect(0f, 0f, w.toFloat(), h.toFloat(), r, r, paint)
        if (colors.coverRing != 0) {
            paint.style = Paint.Style.STROKE; paint.strokeWidth = scale; paint.color = colors.coverRing
            c.drawRoundRect(scale / 2, scale / 2, w - scale / 2, h - scale / 2, r - scale / 2, r - scale / 2, paint)
            paint.style = Paint.Style.FILL
        }
        val m = layers.metrics
        paint.color = colors.coverLine
        c.drawRect(m.left * scale, m.ruleY * scale, m.right * scale, (m.ruleY + 1f) * scale, paint)
        for ((mask, color) in listOf(layers.gilt to colors.giltOnCover, layers.mute to colors.coverMute, layers.ink to colors.onCover)) {
            paint.color = color
            c.drawBitmap(mask, 0f, 0f, paint)
        }
        return out
    }

    private companion object {
        // The design's nominal 4×2, its smallest and tallest, and four cells by two on a launcher that counts in sizes.
        val SIZES = listOf(340f to 180f, 276f to 130f, 360f to 220f, 250f to 110f, 412f to 200f)
        // «بيت اليوم»: the design's 4×2 and its smallest, a Pixel's, the three 2×2 of the design, and two cells by two.
        val DAY_SIZES = listOf(340f to 180f, 276f to 130f, 360f to 232f, 160f to 180f, 140f to 160f, 170f to 210f, 110f to 110f)
        const val DEFAULT_RECORDING = "recording:shatibiyyah:muhammad-atiq-1"
    }
}
