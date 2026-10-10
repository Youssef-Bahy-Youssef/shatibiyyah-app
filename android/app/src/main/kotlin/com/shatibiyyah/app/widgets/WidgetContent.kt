package com.shatibiyyah.app.widgets

import android.content.Context
import android.database.sqlite.SQLiteDatabase
import org.json.JSONObject
import java.io.File

/**
 * A reader's name or symbol inside a hemistich (the snapshot's rumuz_spans): where it is (UTF-16,
 * end exclusive), and whether it is a symbol, which is underlined, or a name, which is not.
 */
internal class WidgetMark(val hemistich: Int, val start: Int, val end: Int, val symbol: Boolean)

/** A verse as a widget shows it. */
internal class WidgetVerse(
    val number: Int,
    val first: String,
    val second: String,
    /** The chapter's short label, for the interface face. */
    val chapterLabel: String,
    /** The chapter's title as the booklet prints it, vocalised. */
    val chapterTitle: String = chapterLabel,
    val marks: List<WidgetMark> = emptyList(),
)

/**
 * The content snapshot, read by the widgets themselves (ADR 0001: it is the only content source),
 * so a widget can draw a verse while the app is not running, and before it has ever run.
 *
 * It is the same installed copy the app reads (lib/data/content_store.dart): the bundled
 * content.sqlite, copied once into files/content/ under a name that carries its content hash.
 * Whichever of the two needs it first installs it.
 */
internal object WidgetContent {
    // Flutter's assets sit under this folder in the APK (the embedding's default).
    private const val ASSETS = "flutter_assets/assets/content/"

    private var db: SQLiteDatabase? = null
    private var key: String? = null

    /** The content's hash, shortened as in the installed file's name. */
    @Synchronized
    fun key(context: Context): String? {
        open(context)
        return key
    }

    @Synchronized
    private fun open(context: Context): SQLiteDatabase? {
        db?.let { if (it.isOpen) return it }
        return try {
            val app = context.applicationContext
            val manifest = JSONObject(app.assets.open(ASSETS + "content.json").use { it.readBytes().toString(Charsets.UTF_8) })
            val sha = manifest.getString("content_sha256").substring(0, 16)
            val bytes = manifest.getLong("bytes")
            val dir = File(app.filesDir, "content")
            val target = File(dir, "content-$sha.sqlite")
            if (!target.exists() || target.length() != bytes) {
                dir.mkdirs()
                // Staged outside content/: the app deletes every other file it finds in there.
                val staging = File(app.filesDir, "content-$sha.widget.part")
                app.assets.open(ASSETS + "content.sqlite").use { input -> staging.outputStream().use { input.copyTo(it) } }
                if (!staging.renameTo(target)) staging.delete()
            }
            // Read-only, and without Android's own locale table, which a foreign database lacks.
            SQLiteDatabase.openDatabase(target.path, null, SQLiteDatabase.OPEN_READONLY or SQLiteDatabase.NO_LOCALIZED_COLLATORS).also {
                db = it
                key = sha
            }
        } catch (_: Exception) {
            null
        }
    }

    @Synchronized
    fun verse(context: Context, number: Int): WidgetVerse? = try {
        val db = open(context)
        db?.rawQuery(
            "SELECT v.first_hemistich, v.second_hemistich, c.short_label, c.title, v.id FROM matn_verses v " +
                "JOIN chapters c ON c.id = v.chapter_id WHERE v.verse_number = ?",
            arrayOf(number.toString()),
        )?.use {
            if (!it.moveToFirst()) return@use null
            val marks = db.rawQuery(
                "SELECT hemistich, start_utf16, end_utf16, kind FROM rumuz_spans WHERE matn_verse_id = ? ORDER BY hemistich, start_utf16",
                arrayOf(it.getString(4)),
            ).use { m ->
                val out = ArrayList<WidgetMark>()
                while (m.moveToNext()) out.add(WidgetMark(m.getInt(0), m.getInt(1), m.getInt(2), m.getString(3) != "name"))
                out
            }
            WidgetVerse(number, it.getString(0), it.getString(1), it.getString(2), it.getString(3), marks)
        }
    } catch (_: Exception) {
        null
    }

    /** How many verses the poem has. */
    @Synchronized
    fun verseCount(context: Context): Int = try {
        open(context)?.rawQuery("SELECT COUNT(*) FROM matn_verses", null)?.use { if (it.moveToFirst()) it.getInt(0) else 0 } ?: 0
    } catch (_: Exception) {
        0
    }

    /** The reciter of [recordingId], by name. */
    @Synchronized
    fun reciter(context: Context, recordingId: String?): String? = try {
        if (recordingId == null) null
        else open(context)?.rawQuery(
            "SELECT r.name FROM recordings g JOIN reciters r ON r.id = g.reciter_id WHERE g.id = ?",
            arrayOf(recordingId),
        )?.use { if (it.moveToFirst()) it.getString(0) else null }
    } catch (_: Exception) {
        null
    }

    /** Every hemistich of the poem, to find the widest. */
    @Synchronized
    fun hemistichs(context: Context): List<String> = try {
        open(context)?.rawQuery("SELECT first_hemistich, second_hemistich FROM matn_verses ORDER BY verse_number", null)?.use {
            val out = ArrayList<String>(2400)
            while (it.moveToNext()) {
                out.add(it.getString(0))
                out.add(it.getString(1))
            }
            out
        } ?: emptyList()
    } catch (_: Exception) {
        emptyList()
    }
}
