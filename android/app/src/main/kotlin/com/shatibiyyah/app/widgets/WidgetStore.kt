package com.shatibiyyah.app.widgets

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

/**
 * What the app last told «تابع» (lib/domain/widget_state.dart). Before the app has ever run this
 * is a new install's state: the first verse, nothing downloaded, the system's theme.
 */
internal data class ResumeState(
    val verse: Int = 1,
    val playing: Boolean = false,
    val audio: Boolean = false,
    val recording: String? = null,
    val theme: String = "auto",
)

/** The widgets' own small store: the published state, and what was asked while the app was not running. */
internal object WidgetStore {
    private const val FILE = "taysir.widgets"
    private const val RESUME = "resume"
    private const val PENDING = "pending"

    private fun prefs(context: Context) = context.applicationContext.getSharedPreferences(FILE, Context.MODE_PRIVATE)

    fun resume(context: Context): ResumeState {
        val raw = prefs(context).getString(RESUME, null) ?: return ResumeState()
        return try {
            val j = JSONObject(raw)
            ResumeState(
                verse = j.getInt("verse"),
                playing = j.optBoolean("playing"),
                audio = j.optBoolean("audio"),
                recording = if (j.isNull("recording")) null else j.optString("recording"),
                theme = j.optString("theme", "auto"),
            )
        } catch (_: Exception) {
            ResumeState()
        }
    }

    /** Stores the state as the app encoded it. */
    fun setResume(context: Context, json: String) = prefs(context).edit().putString(RESUME, json).apply()

    /** The widget's own tap, shown at once; the app's next state confirms or corrects it. */
    fun setPlaying(context: Context, playing: Boolean) {
        val raw = prefs(context).getString(RESUME, null) ?: return
        try {
            setResume(context, JSONObject(raw).put("playing", playing).toString())
        } catch (_: Exception) {
        }
    }

    fun addPending(context: Context, request: Map<String, Any>) {
        val p = prefs(context)
        val list = try {
            JSONArray(p.getString(PENDING, "[]"))
        } catch (_: Exception) {
            JSONArray()
        }
        list.put(JSONObject(request))
        p.edit().putString(PENDING, list.toString()).apply()
    }

    /** The requests kept for the app, oldest first; taking them clears them. */
    fun takePending(context: Context): List<Map<String, Any>> {
        val p = prefs(context)
        val raw = p.getString(PENDING, null) ?: return emptyList()
        p.edit().remove(PENDING).apply()
        return try {
            val list = JSONArray(raw)
            (0 until list.length()).map { i ->
                val o = list.getJSONObject(i)
                o.keys().asSequence().associateWith { k -> o.get(k) }
            }
        } catch (_: Exception) {
            emptyList()
        }
    }
}
