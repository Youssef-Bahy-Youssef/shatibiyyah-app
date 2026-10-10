package com.shatibiyyah.app.widgets

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.SizeF
import android.widget.RemoteViews
import com.shatibiyyah.app.MainActivity
import com.shatibiyyah.app.R

/**
 * «بيت اليوم» (plan 6.2, ADRs 0017 and 0025): one verse a day, in order, from verse 1 on the day
 * the widget is added. It sends no notification and shows no commentary.
 *
 * It changes at local midnight: one alarm is set for the next midnight, and it does not wake the
 * device (a sleeping phone changes when it next wakes). The system's own «time set» and
 * «timezone changed» redraw it too, and so does adding it, resizing it, a restart of the device
 * and a new theme, ink or rubric choice in the app. Nothing else runs.
 */
class DayWidget : AppWidgetProvider() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_MIDNIGHT, Intent.ACTION_TIME_CHANGED, Intent.ACTION_TIMEZONE_CHANGED -> {
                val app = context.applicationContext
                WidgetWork.later(goAsync()) { redraw(app, ids(app), force = true) }
            }
            else -> super.onReceive(context, intent)
        }
    }

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) =
        WidgetWork.later(goAsync()) { redraw(context.applicationContext, ids, force = true) }

    override fun onAppWidgetOptionsChanged(context: Context, manager: AppWidgetManager, id: Int, options: Bundle) =
        WidgetWork.later(goAsync()) { redraw(context.applicationContext, intArrayOf(id), force = true) }

    override fun onDeleted(context: Context, ids: IntArray) {
        for (id in ids) {
            WidgetStore.forgetDay(context, id)
            drawn.remove(id)
        }
    }

    /** The last one is gone: no alarm is left behind. */
    override fun onDisabled(context: Context) {
        (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).cancel(midnight(context))
    }

    companion object {
        const val ACTION_MIDNIGHT = "com.shatibiyyah.app.widget.MIDNIGHT"

        // What each widget last drew, so a state the app publishes redraws it only if it shows in it.
        private val drawn = HashMap<Int, String>()

        private fun ids(context: Context): IntArray =
            AppWidgetManager.getInstance(context).getAppWidgetIds(ComponentName(context, DayWidget::class.java))

        /** Redraws every «بيت اليوم» whose picture would change. */
        fun redrawAll(context: Context) {
            val app = context.applicationContext
            val all = ids(app)
            if (all.isNotEmpty()) WidgetWork.later(null) { redraw(app, all, force = false) }
        }

        /** The verse widget [id] shows on [today]; the day it was added is noted the first time. */
        internal fun verseFor(context: Context, id: Int, today: String, verses: Int): Int {
            val added = WidgetStore.dayAdded(context, id) ?: today.also { WidgetStore.setDayAdded(context, id, it) }
            return DailyVerse.verse(added, today, verses)
        }

        private fun redraw(context: Context, ids: IntArray, force: Boolean) {
            if (ids.isEmpty()) return
            val manager = AppWidgetManager.getInstance(context)
            val state = WidgetStore.resume(context)
            val today = DailyVerse.today()
            val verses = WidgetContent.verseCount(context)
            for (id in ids) {
                val number = verseFor(context, id, today, verses)
                val options = manager.getAppWidgetOptions(id)
                val sizes = ResumeWidget.sizes(options)
                val picture = "$number|${state.theme}|${state.ink}|${state.rubric}|$sizes"
                if (!force && drawn[id] == picture) continue
                val verse = WidgetContent.verse(context, number) ?: continue
                val each = sizes.map { it to viewsAt(context, it, state, verse) }
                manager.updateAppWidget(id, when {
                    each.size == 1 -> each[0].second
                    Build.VERSION.SDK_INT >= 31 -> RemoteViews(each.toMap())
                    else -> RemoteViews(each[1].second, each[0].second) // on its side, upright
                })
                drawn[id] = picture
            }
            schedule(context)
        }

        /** One alarm at the next local midnight. It is inexact and does not wake the device. */
        private fun schedule(context: Context) {
            (context.getSystemService(Context.ALARM_SERVICE) as AlarmManager).set(AlarmManager.RTC, DailyVerse.nextMidnight(), midnight(context))
        }

        private fun midnight(context: Context): PendingIntent = PendingIntent.getBroadcast(
            context, 0, Intent(context, DayWidget::class.java).setAction(ACTION_MIDNIGHT),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        private fun viewsAt(context: Context, size: SizeF, state: ResumeState, verse: WidgetVerse): RemoteViews {
            val density = context.resources.displayMetrics.density
            val spec = DaySpec(size.width, size.height, verse, state.rubric)
            val layers = DayPainter.draw(context, spec, density)
            val m = layers.metrics
            fun px(dp: Float) = Math.round(dp * density)
            // «تلقائي»: the layout's own day and night colours. A chosen theme: its colours, set here.
            val fixed = when (state.theme) {
                "paper" -> WidgetTokens.paper
                "night" -> WidgetTokens.night
                else -> null
            }
            val ink = WidgetTokens.nightInks[state.ink] ?: WidgetTokens.nightInks.getValue(WidgetTokens.defaultNightInk)
            val views = RemoteViews(context.packageName, if (fixed == null) R.layout.widget_day else R.layout.widget_day_fixed)
            fun place(box: Int, image: Int, band: Band) {
                views.setImageViewBitmap(image, band.bitmap)
                views.setViewPadding(box, 0, px(band.top), 0, px(size.height) - px(band.bottom))
            }
            place(R.id.widget_day_box_gilt, R.id.widget_day_gilt, layers.gilt)
            place(R.id.widget_day_box_number, R.id.widget_day_number, layers.number)
            place(R.id.widget_day_box_chapter, R.id.widget_day_chapter, layers.chapter)
            place(R.id.widget_day_box_verse, R.id.widget_day_verse, layers.verse)
            views.setViewPadding(R.id.widget_day_rule_box, px(m.left), px(m.ruleY), px(m.left), 0)
            views.setViewPadding(R.id.widget_day_box_rubric, 0, px(layers.rubric.top), 0, px(size.height) - px(layers.rubric.bottom))
            if (fixed == null) {
                // The rubric by day is the booklet's crimson; at night, the reader's chosen ink. Each
                // view shows only in its own half of the day (its alpha is a day or night resource).
                views.setImageViewBitmap(R.id.widget_day_rubric_day, layers.rubric.bitmap)
                views.setImageViewBitmap(R.id.widget_day_rubric_night, layers.rubric.bitmap)
                views.setInt(R.id.widget_day_rubric_night, "setColorFilter", ink)
            } else {
                val night = fixed === WidgetTokens.night
                views.setImageViewResource(R.id.widget_day_bg, if (night) R.drawable.widget_leaf_night else R.drawable.widget_leaf_paper)
                views.setImageViewBitmap(R.id.widget_day_rubric, layers.rubric.bitmap)
                views.setInt(R.id.widget_day_rubric, "setColorFilter", if (night) ink else fixed.rubric)
                views.setInt(R.id.widget_day_verse, "setColorFilter", fixed.verseInk)
                views.setInt(R.id.widget_day_chapter, "setColorFilter", fixed.ink2)
                views.setInt(R.id.widget_day_number, "setColorFilter", fixed.ink)
                views.setInt(R.id.widget_day_gilt, "setColorFilter", fixed.gilt)
                views.setInt(R.id.widget_day_rule, "setBackgroundColor", fixed.gilt)
            }
            views.setContentDescription(R.id.widget_day_root, DayPainter.description(spec))
            val open = Intent(context, MainActivity::class.java)
                .setAction(WidgetBridge.ACTION_OPEN)
                .setData(Uri.parse("taysir://widget/verse/${verse.number}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            views.setOnClickPendingIntent(R.id.widget_day_root, PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE))
            return views
        }
    }
}
