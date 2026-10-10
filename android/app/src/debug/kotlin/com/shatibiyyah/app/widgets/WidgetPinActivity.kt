package com.shatibiyyah.app.widgets

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.os.Bundle

/**
 * Debug builds only: asks the launcher to put «تابع» on the home screen, so a device check does
 * not have to find it in the widget picker (tool/widget_check.sh).
 *
 *     adb shell am start -n <package>/com.shatibiyyah.app.widgets.WidgetPinActivity
 */
class WidgetPinActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val manager = AppWidgetManager.getInstance(this)
        if (manager.isRequestPinAppWidgetSupported) {
            manager.requestPinAppWidget(ComponentName(this, ResumeWidget::class.java), null, null)
        }
        finish()
    }
}
