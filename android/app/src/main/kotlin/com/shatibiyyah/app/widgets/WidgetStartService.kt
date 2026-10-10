package com.shatibiyyah.app.widgets

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import com.shatibiyyah.app.R

/**
 * ▶ on «تابع» while nothing of the app is running: starts the app with no screen and keeps the
 * process in the foreground until the recitation plays.
 *
 * A broadcast alone cannot do this. The app takes a few seconds to start, more than a broadcast
 * may be held open, and a process with nothing in the foreground may be frozen in the middle. So
 * for those seconds this service stands in, with a notice that the recitation is starting. Once
 * the app has published its state the audio service has its own notification, and this one goes.
 */
class WidgetStartService : Service() {
    private val main = Handler(Looper.getMainLooper())
    private val giveUp = Runnable { done(started = false) }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (Build.VERSION.SDK_INT >= 29) {
            startForeground(NOTICE_ID, notice(), ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
        } else {
            startForeground(NOTICE_ID, notice())
        }
        if (!starting) {
            starting = true
            main.postDelayed(giveUp, START_LIMIT_MS)
            // After this turn: the notice is up before the engine, which takes the main thread a while.
            main.post { WidgetBridge.startWithoutScreen(applicationContext) { done(started = true) } }
        }
        return START_NOT_STICKY
    }

    private fun done(started: Boolean) {
        if (!starting) return
        starting = false
        main.removeCallbacks(giveUp)
        // The app did not come up: the widget goes back to ▶. Otherwise it has just drawn what the app published.
        if (!started) {
            WidgetStore.setPlaying(applicationContext, false)
            ResumeWidget.redrawAll(applicationContext)
        }
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else @Suppress("DEPRECATION") stopForeground(true)
        stopSelf()
    }

    override fun onDestroy() {
        starting = false
        main.removeCallbacks(giveUp)
        super.onDestroy()
    }

    private fun notice(): Notification {
        if (Build.VERSION.SDK_INT >= 26) {
            // The audio service's own channel (lib/main.dart): the same one, made here if this comes first.
            val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            if (manager.getNotificationChannel(CHANNEL) == null) {
                manager.createNotificationChannel(NotificationChannel(CHANNEL, "تيسير الشاطبية", NotificationManager.IMPORTANCE_LOW))
            }
        }
        @Suppress("DEPRECATION")
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, CHANNEL) else Notification.Builder(this)
        return builder
            .setSmallIcon(R.drawable.ic_stat_taysir)
            .setContentTitle("تيسير الشاطبية")
            .setContentText("جارٍ تشغيل التلاوة…")
            .setOngoing(true)
            .build()
    }

    companion object {
        /** True from ▶ until the app has published or the start was given up: the widget shows ❚❚ meanwhile. */
        @Volatile
        internal var starting = false
            private set

        private const val CHANNEL = "app.shatibiyyah.hirz.channel.audio"
        private const val NOTICE_ID = 4611
        private const val START_LIMIT_MS = 30_000L

        internal fun start(context: Context) {
            val intent = Intent(context, WidgetStartService::class.java)
            if (Build.VERSION.SDK_INT >= 26) context.startForegroundService(intent) else context.startService(intent)
        }
    }
}
