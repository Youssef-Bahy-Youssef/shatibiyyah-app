package com.shatibiyyah.app.widgets

import android.content.Context
import android.graphics.Paint
import android.graphics.Typeface

/** A number in Arabic-Indic digits, as the app's `ar()` writes it. */
internal fun arabicDigits(n: Int): String = n.toString().map { if (it in '0'..'9') '٠' + (it - '0') else it }.joinToString("")

private val TASHKEEL = Regex("[ً-ْٰ]")

/** A chapter's name for the interface face: plain (lib/utils/arabic.dart, `plainName`). */
internal fun plainName(s: String): String = TASHKEEL.replace(s, "")

/** The name as the reading screen's top bar gives it: plain, without a leading «باب» (`chapterBarTitle`). */
internal fun barTitle(shortLabel: String): String = plainName(shortLabel).removePrefix("باب ")

/** The app's two faces, from the font files Flutter bundles. */
internal object WidgetFonts {
    private const val DIR = "flutter_assets/assets/fonts/"
    private val cache = HashMap<String, Typeface>()

    @Synchronized
    private fun face(context: Context, file: String): Typeface = cache.getOrPut(file) {
        try {
            Typeface.createFromAsset(context.applicationContext.assets, DIR + file)
        } catch (_: Exception) {
            Typeface.DEFAULT
        }
    }

    /** Scheherazade New: the poem. */
    fun verse(context: Context) = face(context, "ScheherazadeNew-Regular.ttf")
    fun chapter(context: Context) = face(context, "ScheherazadeNew-Medium.ttf")

    /** IBM Plex Sans Arabic: every interface label. */
    fun ui(context: Context) = face(context, "IBMPlexSansArabic-Regular.ttf")
    fun uiSemiBold(context: Context) = face(context, "IBMPlexSansArabic-SemiBold.ttf")
}

/**
 * The widest hemistich of the poem in em of the verse face, as this device shapes it. The verse
 * size of a 4×2 widget follows from it (ADR 0025), so no verse can be wider than its line.
 * Measured once per content and kept.
 */
internal object WidestHemistich {
    private const val FILE = "taysir.widgets"

    @Synchronized
    fun em(context: Context): Float {
        val key = "widest." + (WidgetContent.key(context) ?: return FALLBACK)
        val prefs = context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)
        val kept = prefs.getFloat(key, 0f)
        if (kept > 0f) return kept
        val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply { typeface = WidgetFonts.verse(context); textSize = 100f }
        val widest = WidgetContent.hemistichs(context).maxOfOrNull { paint.measureText(it) } ?: return FALLBACK
        val em = widest / 100f
        prefs.edit().putFloat(key, em).apply()
        return em
    }

    // The design's measure (verse 336 in Chromium), used only if the content cannot be read.
    private const val FALLBACK = 14.61f
}
