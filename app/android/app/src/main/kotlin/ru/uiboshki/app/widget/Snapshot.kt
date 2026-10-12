package ru.uiboshki.app.widget

// Снимок дня от приложения (lib/widget_data.dart) и что из него показать
// сейчас. Время виджет берёт своё: «через 12 мин» считается от текущей
// минуты, день — по дате в Москве (снимок может быть и вчерашним).

import android.content.Context
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

data class WLesson(
    val start: String,
    val end: String,
    val startAt: Long,
    val endAt: Long,
    val title: String,
    val room: String,
)

data class WDay(val date: String, val header: String, val partial: Boolean, val lessons: List<WLesson>)

data class WDeadline(val title: String, val due: Long)

data class Snapshot(val at: Long, val days: List<WDay>, val deadline: WDeadline?)

/** Что показать маленькому виджету. */
sealed class LessonState {
    /** Снимка нет или он старый — «Открой Капибару». */
    object NoData : LessonState()

    /** Пар ни сегодня (больше), ни завтра. */
    object Free : LessonState()

    data class Now(val lesson: WLesson, val minutesLeft: Int) : LessonState()

    data class Next(val lesson: WLesson, val minutes: Int, val tomorrow: Boolean) : LessonState()
}

object WidgetStore {
    private const val PREFS = "kapibara_widget"
    private const val KEY = "snapshot"

    /** null — стереть (новый дизайн выключен или вышли из аккаунта). */
    fun save(ctx: Context, json: String?) {
        val e = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
        if (json == null) e.remove(KEY) else e.putString(KEY, json)
        e.apply()
    }

    fun load(ctx: Context): Snapshot? =
        parse(ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(KEY, null))

    fun parse(json: String?): Snapshot? {
        if (json.isNullOrEmpty()) return null
        return try {
            val o = JSONObject(json)
            val days = mutableListOf<WDay>()
            val arr = o.optJSONArray("days")
            if (arr != null) {
                for (i in 0 until arr.length()) {
                    val d = arr.optJSONObject(i) ?: continue
                    val lessons = mutableListOf<WLesson>()
                    val la = d.optJSONArray("l")
                    if (la != null) {
                        for (j in 0 until la.length()) {
                            val l = la.optJSONObject(j) ?: continue
                            lessons.add(
                                WLesson(
                                    l.optString("s"),
                                    l.optString("e"),
                                    l.optLong("sa"),
                                    l.optLong("ea"),
                                    l.optString("t"),
                                    l.optString("r"),
                                ),
                            )
                        }
                    }
                    days.add(WDay(d.optString("d"), d.optString("h"), d.optBoolean("part"), lessons))
                }
            }
            val dl = o.optJSONObject("dl")
            Snapshot(o.optLong("at"), days, dl?.let { WDeadline(it.optString("t"), it.optLong("due")) })
        } catch (e: Exception) {
            null
        }
    }
}

object Schedule {
    private const val MINUTE = 60_000L
    private const val HOUR = 60 * MINUTE
    private const val DAY = 24 * HOUR
    private val msk: TimeZone = TimeZone.getTimeZone("Europe/Moscow")

    fun mskDate(t: Long): String =
        SimpleDateFormat("yyyy-MM-dd", Locale.US).apply { timeZone = msk }.format(Date(t))

    /** Минут до момента с округлением вверх: за 30 секунд до начала — «1», не «0». */
    fun minutesUntil(now: Long, t: Long): Int = ((t - now + MINUTE - 1) / MINUTE).toInt().coerceAtLeast(0)

    private fun today(s: Snapshot, now: Long) = s.days.firstOrNull { it.date == mskDate(now) }

    private fun tomorrow(s: Snapshot, now: Long) = s.days.firstOrNull { it.date == mskDate(now + DAY) }

    fun state(s: Snapshot?, now: Long): LessonState {
        if (s == null) return LessonState.NoData
        val today = today(s, now)
        val tomorrow = tomorrow(s, now)
        if (today == null && tomorrow == null) return LessonState.NoData
        today?.lessons?.firstOrNull { it.startAt <= now && now < it.endAt }?.let {
            return LessonState.Now(it, minutesUntil(now, it.endAt))
        }
        today?.lessons?.firstOrNull { it.startAt > now }?.let {
            return LessonState.Next(it, minutesUntil(now, it.startAt), false)
        }
        tomorrow?.lessons?.firstOrNull()?.let {
            return LessonState.Next(it, minutesUntil(now, it.startAt), true)
        }
        return LessonState.Free
    }

    /** День для большого виджета: сегодня, пока пары не кончились, потом завтра. Второе — это завтра. */
    fun dayToShow(s: Snapshot?, now: Long): Pair<WDay, Boolean>? {
        if (s == null) return null
        val today = today(s, now)
        val tomorrow = tomorrow(s, now)
        if (today != null && today.lessons.any { it.endAt > now }) return today to false
        if (tomorrow != null) return tomorrow to true
        return today?.let { it to false }
    }

    /** «через 12 мин», «через 1 ч 05 мин», «сегодня в 16:20», «завтра в 9:00». */
    fun nextLabel(n: LessonState.Next): String = when {
        n.tomorrow -> "завтра в ${n.lesson.start}"
        n.minutes < 60 -> "через ${n.minutes} мин"
        n.minutes < 180 -> "через ${n.minutes / 60} ч ${(n.minutes % 60).toString().padStart(2, '0')} мин"
        else -> "сегодня в ${n.lesson.start}"
    }

    /** Сколько до срока коротко: «45 мин», «13 ч», «2 дн». */
    fun leftShort(now: Long, due: Long): String {
        val m = minutesUntil(now, due)
        return when {
            m < 60 -> "$m мин"
            m < 48 * 60 -> "${m / 60} ч"
            else -> "${m / (24 * 60)} дн"
        }
    }

    /** Горящий срок, если ещё не прошёл. */
    fun deadline(s: Snapshot?, now: Long): WDeadline? = s?.deadline?.takeIf { it.due > now && it.title.isNotEmpty() }

    /**
     * Когда пересчитать виджет: каждую минуту, пока пара идёт или до неё меньше
     * трёх часов, иначе — к ближайшей границе (за три часа до пары, начало,
     * конец, полночь по Москве). null — нечего ждать.
     */
    fun nextTick(s: Snapshot?, now: Long): Long? {
        if (s == null) return null
        val all = s.days.flatMap { it.lessons }
        if (all.any { now < it.endAt && it.startAt - 3 * HOUR <= now }) return (now / MINUTE + 1) * MINUTE
        val midnight = Calendar.getInstance(msk).apply {
            timeInMillis = now
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 0)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis
        return (all.flatMap { listOf(it.startAt - 3 * HOUR, it.startAt, it.endAt) } + midnight)
            .filter { it > now }
            .minOrNull()
    }
}
