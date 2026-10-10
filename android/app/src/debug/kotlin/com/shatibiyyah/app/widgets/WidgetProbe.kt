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
 * Debug builds only: checks «تابع»'s drawing on a real Android, where its text is shaped and
 * measured (tool/widget_check.sh runs it and reads the result).
 *
 *     adb shell am broadcast -n <package>/com.shatibiyyah.app.widgets.WidgetProbe
 *
 * For every verse of the poem, at each size and font scale, it checks that both hemistichs fit
 * their line and that their ink stays between the hairline and the widget's edge. It then draws
 * the states of the design (design/redesign/widgets/) as PNG files, to set beside its renders,
 * and redraws the widgets that are on the home screen. The result is
 * files/widget-probe/report.json in the app's external files.
 */
class WidgetProbe : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        val app = context.applicationContext
        thread {
            try {
                run(app)
            } finally {
                pending.finish()
            }
        }
    }

    private fun run(context: Context) {
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

            // The widgets on the home screen now: the sizes the launcher gives them, and what one drawing weighs.
            val manager = AppWidgetManager.getInstance(context)
            val placed = JSONArray()
            for (id in manager.getAppWidgetIds(ComponentName(context, ResumeWidget::class.java))) {
                val sizes = ResumeWidget.sizes(manager.getAppWidgetOptions(id))
                val bytes = sizes.sumOf { 3L * Math.round(it.width * density) * Math.round(it.height * density) }
                placed.put(JSONObject().put("id", id).put("sizesDp", sizes.joinToString { "${it.width}x${it.height}" }).put("maskBytes", bytes))
            }
            val screen = context.resources.displayMetrics
            report.put("placed", placed).put("bitmapLimitBytes", 6L * screen.widthPixels * screen.heightPixels)
            report.put("ok", true)
        } catch (e: Exception) {
            report.put("ok", false).put("error", e.toString())
        }
        File(out, "report.json").writeText(report.toString(2))
        // And the placed widgets are drawn again, as after a change of state.
        ResumeWidget.redrawAll(context)
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
        const val DEFAULT_RECORDING = "recording:shatibiyyah:muhammad-atiq-1"
    }
}
