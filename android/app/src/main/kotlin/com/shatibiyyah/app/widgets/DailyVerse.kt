package com.shatibiyyah.app.widgets

import java.util.Calendar

/**
 * «بيت اليوم»: which verse a day shows (ADRs 0017, 0025). The same arithmetic as
 * lib/domain/daily_verse.dart, done here because the widget changes at midnight with the app
 * closed; both are held to test/fixtures/daily_verse.json.
 *
 * A day is a local calendar date, written «YYYY-MM-DD». Only the dates count, not the hours
 * between them: a day of 23 or 25 hours and a change of timezone are each one step per date.
 */
internal object DailyVerse {
    /** The verse (1…[verses]) for [today], for a widget added on [added]; the first one if the clock was set back. */
    fun verse(added: String, today: String, verses: Int): Int {
        if (verses <= 0) return 1
        val days = dayNumber(today) - dayNumber(added)
        return ((if (days < 0) 0 else days) % verses).toInt() + 1
    }

    /** Days since 1970-01-01 of a civil date (the Gregorian calendar, with no timezone in it). */
    fun dayNumber(date: String): Long {
        val (y0, m, d) = date.split("-").map { it.toInt() }
        val y = if (m <= 2) y0 - 1 else y0
        val era = (if (y >= 0) y else y - 399) / 400
        val yoe = y - era * 400
        val doy = (153 * (m + (if (m > 2) -3 else 9)) + 2) / 5 + d - 1
        val doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097L + doe - 719468L
    }

    /** The device's date now. */
    fun today(now: Calendar = Calendar.getInstance()): String =
        "%04d-%02d-%02d".format(java.util.Locale.ROOT, now.get(Calendar.YEAR), now.get(Calendar.MONTH) + 1, now.get(Calendar.DAY_OF_MONTH))

    /** The next local midnight after [now], as a wall-clock instant. */
    fun nextMidnight(now: Calendar = Calendar.getInstance()): Long {
        val next = now.clone() as Calendar
        next.add(Calendar.DAY_OF_MONTH, 1)
        next.set(Calendar.HOUR_OF_DAY, 0)
        next.set(Calendar.MINUTE, 0)
        next.set(Calendar.SECOND, 0)
        next.set(Calendar.MILLISECOND, 0)
        return next.timeInMillis
    }
}
