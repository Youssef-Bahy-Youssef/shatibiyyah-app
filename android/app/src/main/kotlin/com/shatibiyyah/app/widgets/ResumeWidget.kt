package com.shatibiyyah.app.widgets

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.view.View
import android.widget.RemoteViews
import com.shatibiyyah.app.MainActivity
import com.shatibiyyah.app.R
import java.util.concurrent.Executors

/**
 * «تابع» (plan 6.1, ADRs 0017 and 0025): the current verse, with ▶/❚❚.
 *
 * It is redrawn only when something changes: the app publishes a new state (at most once in five
 * seconds), the widget is tapped, added or resized, or the device restarts. There is no timer.
 */
class ResumeWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = later(goAsync()) { redraw(context, ids) }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) =
        later(goAsync()) { redraw(context, intArrayOf(id)) }

    companion object {
        // One at a time, off the main thread: the first drawing installs the content and measures the poem.
        private val work = Executors.newSingleThreadExecutor()

        private fun later(pending: BroadcastReceiver.PendingResult?, task: () -> Unit) {
            work.execute {
                try {
                    task()
                } catch (_: Exception) {
                } finally {
                    pending?.finish()
                }
            }
        }

        /** Redraws every «تابع» on the home screen, if there is one. */
        fun redrawAll(context: Context) {
            val app = context.applicationContext
            val ids = AppWidgetManager.getInstance(app).getAppWidgetIds(ComponentName(app, ResumeWidget::class.java))
            if (ids.isNotEmpty()) later(null) { redraw(app, ids) }
        }

        /**
         * What the widget shows now: the published state, but never "playing" when nothing of the
         * app is running (unless ▶ has just started it).
         */
        internal fun shown(context: Context): ResumeState {
            val state = WidgetStore.resume(context)
            return if (state.playing && !WidgetBridge.ready() && !WidgetStartService.starting) state.copy(playing = false) else state
        }

        private fun redraw(context: Context, ids: IntArray) {
            val manager = AppWidgetManager.getInstance(context)
            val state = shown(context)
            val verse = WidgetContent.verse(context, state.verse) ?: WidgetContent.verse(context, 1) ?: return
            val reciter = WidgetContent.reciter(context, state.recording)
            for (id in ids) manager.updateAppWidget(id, views(context, manager.getAppWidgetOptions(id), state, verse, reciter))
        }

        /** The sizes the launcher shows this widget at, in dp. */
        internal fun sizes(options: Bundle): List<SizeF> {
            if (Build.VERSION.SDK_INT >= 31) {
                val exact = options.getParcelableArrayList<SizeF>(AppWidgetManager.OPTION_APPWIDGET_SIZES)
                if (!exact.isNullOrEmpty()) return exact.distinct()
            }
            // Upright it is as narrow and as tall as it gets; on its side, as wide and as short.
            val minW = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH)
            val maxW = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH)
            val minH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT)
            val maxH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT)
            if (minW <= 0 || maxH <= 0) return listOf(SizeF(DEFAULT_WIDTH, DEFAULT_HEIGHT))
            return listOf(SizeF(minW.toFloat(), maxH.toFloat()), SizeF(max(maxW, minW).toFloat(), min(minH, maxH).coerceAtLeast(1).toFloat())).distinct()
        }

        private fun max(a: Int, b: Int) = if (a > b) a else b
        private fun min(a: Int, b: Int) = if (a < b) a else b

        private fun views(context: Context, options: Bundle, state: ResumeState, verse: WidgetVerse, reciter: String?): RemoteViews {
            val sizes = sizes(options)
            val each = sizes.map { it to viewsAt(context, it, state, verse, reciter) }
            return when {
                each.size == 1 -> each[0].second
                Build.VERSION.SDK_INT >= 31 -> RemoteViews(each.toMap())
                else -> RemoteViews(each[1].second, each[0].second) // on its side, upright
            }
        }

        private fun viewsAt(context: Context, size: SizeF, state: ResumeState, verse: WidgetVerse, reciter: String?): RemoteViews {
            val res = context.resources
            val density = res.displayMetrics.density
            val spec = ResumeSpec(size.width, size.height, state, verse, reciter, res.configuration.fontScale)
            val layers = ResumePainter.draw(context, spec, density)
            // «تلقائي»: the layout's own colours, which are day and night resources. A chosen theme: its colours, set here.
            val fixed = when (state.theme) {
                "paper" -> WidgetTokens.paper
                "night" -> WidgetTokens.night
                else -> null
            }
            val views = RemoteViews(context.packageName, if (fixed == null) R.layout.widget_resume else R.layout.widget_resume_fixed)
            views.setImageViewBitmap(R.id.widget_ink, layers.ink)
            views.setImageViewBitmap(R.id.widget_mute, layers.mute)
            views.setImageViewBitmap(R.id.widget_gilt, layers.gilt)
            val m = layers.metrics
            fun px(dp: Float) = Math.round(dp * density)
            views.setViewPadding(R.id.widget_rule_box, px(m.left), px(m.ruleY), px(m.left), 0)
            if (fixed != null) {
                views.setImageViewResource(R.id.widget_bg, if (fixed === WidgetTokens.night) R.drawable.widget_cover_night else R.drawable.widget_cover_paper)
                views.setInt(R.id.widget_ink, "setColorFilter", fixed.onCover)
                views.setInt(R.id.widget_mute, "setColorFilter", fixed.coverMute)
                views.setInt(R.id.widget_gilt, "setColorFilter", fixed.giltOnCover)
                views.setInt(R.id.widget_rule, "setBackgroundColor", fixed.coverLine)
            }
            views.setContentDescription(R.id.widget_root, ResumePainter.description(spec))
            views.setOnClickPendingIntent(R.id.widget_root, open(context, "verse/${verse.number}"))

            // One control: ▶ or ❚❚ over the disc, or the wider «تنزيل» when the recording is not on the device.
            views.setViewVisibility(R.id.widget_button, if (state.audio) View.VISIBLE else View.GONE)
            views.setViewVisibility(R.id.widget_button_wide, if (state.audio) View.GONE else View.VISIBLE)
            if (state.audio) {
                views.setContentDescription(R.id.widget_button, if (state.playing) "إيقاف مؤقت" else "تشغيل")
                views.setOnClickPendingIntent(R.id.widget_button, action(context, if (state.playing) WidgetActions.PAUSE else WidgetActions.PLAY))
            } else {
                views.setOnClickPendingIntent(R.id.widget_button_wide, open(context, "downloads"))
            }
            return views
        }

        /** Opens the app on what was tapped: `verse/N` or `downloads`. */
        private fun open(context: Context, what: String): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setAction(WidgetBridge.ACTION_OPEN)
                .setData(Uri.parse("taysir://widget/$what"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        private fun action(context: Context, name: String): PendingIntent {
            val intent = Intent(context, WidgetActions::class.java).setAction(name)
            return PendingIntent.getBroadcast(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        }

        // The design's nominal 4×2, for a launcher that reports no size.
        private const val DEFAULT_WIDTH = 340f
        private const val DEFAULT_HEIGHT = 180f
    }
}
