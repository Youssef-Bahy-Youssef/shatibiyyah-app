package com.shatibiyyah.app.widgets

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.os.Bundle

/**
 * Debug builds only: asks the launcher to put a widget on the home screen, so a device check does
 * not have to find it in the widget picker.
 *
 *     adb shell am start -n <package>/com.shatibiyyah.app.widgets.WidgetPinActivity            «تابع»
 *     adb shell am start -n <package>/com.shatibiyyah.app.widgets.WidgetPinActivity --es widget day
 */
class WidgetPinActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val manager = AppWidgetManager.getInstance(this)
        if (manager.isRequestPinAppWidgetSupported) {
            val provider = if (intent.getStringExtra("widget") == "day") DayWidget::class.java else ResumeWidget::class.java
            manager.requestPinAppWidget(ComponentName(this, provider), null, null)
        }
        finish()
    }
}
