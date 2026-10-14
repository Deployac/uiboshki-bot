package ru.uiboshki.app.widget

// Виджеты рабочего стола: «Пара» (2×2 — следующая пара или сколько до конца
// текущей) и «Весь день» (4×4 — пары дня и горящий срок). Цвета — в
// res/values(-night)/widget_colors.xml: светлый как «Тетрадь», тёмный как
// «Глубина», по теме телефона. Пересчёт — при записи снимка приложением, раз в
// 30 минут (updatePeriodMillis) и будильником без пробуждения (RTC): раз в
// минуту рядом с парой, пока экран включён.

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import ru.uiboshki.app.R

object Widgets {
    /** Сколько виджетов Капибары стоит на экранах. */
    fun count(ctx: Context): Int {
        val m = AppWidgetManager.getInstance(ctx)
        return m.getAppWidgetIds(ComponentName(ctx, LessonWidget::class.java)).size +
            m.getAppWidgetIds(ComponentName(ctx, DayWidget::class.java)).size
    }

    /** Перерисовать все виджеты по снимку и завести следующий пересчёт. */
    fun updateAll(ctx: Context) {
        val m = AppWidgetManager.getInstance(ctx)
        val snap = WidgetStore.load(ctx)
        val now = System.currentTimeMillis()
        val small = m.getAppWidgetIds(ComponentName(ctx, LessonWidget::class.java))
        val big = m.getAppWidgetIds(ComponentName(ctx, DayWidget::class.java))
        if (small.isNotEmpty()) m.updateAppWidget(small, renderLesson(ctx, snap, now))
        if (big.isNotEmpty()) m.updateAppWidget(big, renderDay(ctx, snap, now))
        schedule(ctx, if (small.isEmpty() && big.isEmpty()) null else Schedule.nextTick(snap, now))
    }

    private fun schedule(ctx: Context, at: Long?) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val intent = Intent(ctx, WidgetTickReceiver::class.java).setAction(WidgetTickReceiver.ACTION)
        val pi = PendingIntent.getBroadcast(
            ctx,
            0,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        // RTC без WAKEUP: спящий телефон не будим, догоним при включении экрана
        if (at == null) am.cancel(pi) else am.set(AlarmManager.RTC, at, pi)
    }

    /** Нажатие — открыть приложение (оно начинает с «Сегодня»). */
    private fun openApp(ctx: Context): PendingIntent? {
        val launch = ctx.packageManager.getLaunchIntentForPackage(ctx.packageName) ?: return null
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return PendingIntent.getActivity(
            ctx,
            0,
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    /** Цвет текста из ресурса: с Android 12 его берёт рабочий стол — сам следит за темой. */
    private fun RemoteViews.textColor(ctx: Context, id: Int, color: Int) {
        if (Build.VERSION.SDK_INT >= 31) setColor(id, "setTextColor", color) else setTextColor(id, ctx.getColor(color))
    }

    fun renderLesson(ctx: Context, snap: Snapshot?, now: Long): RemoteViews {
        val v = RemoteViews(ctx.packageName, R.layout.widget_lesson)
        openApp(ctx)?.let { v.setOnClickPendingIntent(R.id.w_root, it) }
        var label = ""
        var big: String
        var sub: String
        var labelColor = R.color.w_accent
        when (val st = Schedule.state(snap, now)) {
            is LessonState.NoData -> {
                big = "Капибара"
                sub = "Открой приложение — здесь появятся пары"
            }
            is LessonState.Free -> {
                label = "сегодня и завтра"
                big = "Пар нет"
                sub = "Можно выдохнуть"
                labelColor = R.color.w_muted
            }
            is LessonState.Now -> {
                val l = st.lesson
                label = if (l.room.isEmpty()) "идёт" else "идёт · ${l.room}"
                big = "${st.minutesLeft}’"
                // до конца текущей пары, не всего блока военки («530′», 14.10)
                val after = Schedule.after(snap, now, l)
                sub = when {
                    l.inBlock -> "до конца пары · ${l.n} из ${l.of}, всё до ${l.blockEnd.ifEmpty { l.end }}"
                    after != null -> "до конца пары · дальше ${after.start} ${after.room}".trimEnd()
                    else -> "до конца пары · последняя"
                }
                labelColor = R.color.w_ok
            }
            is LessonState.Next -> {
                val l = st.lesson
                val pause = !st.tomorrow && l.inBlock && l.n > 1
                label = if (pause) "перемена · ${st.minutes} мин" else Schedule.nextLabel(st)
                if (pause) labelColor = R.color.w_ok
                big = l.room.ifEmpty { l.start }
                sub = if (l.inBlock) "${l.title} · пара ${l.n} из ${l.of}" else "${l.title} · ${l.start}–${l.end}"
            }
        }
        v.setTextViewText(R.id.w_label, label)
        v.setViewVisibility(R.id.w_label, if (label.isEmpty()) View.GONE else View.VISIBLE)
        v.textColor(ctx, R.id.w_label, labelColor)
        v.setTextViewText(R.id.w_big, big)
        v.setTextViewText(R.id.w_sub, sub)
        return v
    }

    fun renderDay(ctx: Context, snap: Snapshot?, now: Long): RemoteViews {
        val v = RemoteViews(ctx.packageName, R.layout.widget_day)
        openApp(ctx)?.let { v.setOnClickPendingIntent(R.id.w_root, it) }
        v.removeAllViews(R.id.w_rows)
        val shown = Schedule.dayToShow(snap, now)
        if (shown == null) {
            v.setTextViewText(R.id.w_head, "КАПИБАРА")
            v.setTextViewText(R.id.w_empty, "Открой приложение — здесь появятся пары")
            v.setViewVisibility(R.id.w_empty, View.VISIBLE)
        } else {
            val (day, tomorrow) = shown
            v.setTextViewText(R.id.w_head, if (tomorrow) "ЗАВТРА · ${day.header}" else day.header)
            for (l in Schedule.rows(day).take(8)) {
                val row = RemoteViews(ctx.packageName, R.layout.widget_day_row)
                row.setTextViewText(R.id.row_time, l.start)
                row.setTextViewText(R.id.row_title, l.title)
                row.setTextViewText(R.id.row_room, l.room)
                val color = when {
                    l.startAt <= now && now < l.endAt -> R.color.w_ok
                    l.endAt <= now -> R.color.w_muted
                    else -> R.color.w_text
                }
                for (id in intArrayOf(R.id.row_time, R.id.row_title, R.id.row_room)) row.textColor(ctx, id, color)
                v.addView(R.id.w_rows, row)
            }
            val empty = day.lessons.isEmpty()
            v.setTextViewText(R.id.w_empty, if (empty) "Пар нет — можно выдохнуть" else "")
            v.setViewVisibility(R.id.w_empty, if (empty) View.VISIBLE else View.GONE)
        }
        val dl = Schedule.deadline(snap, now)
        if (dl == null) {
            v.setViewVisibility(R.id.w_deadline, View.GONE)
        } else {
            v.setTextViewText(R.id.w_deadline, "${dl.title} · ${Schedule.leftShort(now, dl.due)}")
            v.setViewVisibility(R.id.w_deadline, View.VISIBLE)
        }
        return v
    }
}

/** «Пара» — 2×2. */
class LessonWidget : AppWidgetProvider() {
    override fun onUpdate(ctx: Context, manager: AppWidgetManager, ids: IntArray) = Widgets.updateAll(ctx)

    override fun onDisabled(ctx: Context) = Widgets.updateAll(ctx)
}

/** «Весь день» — 4×4. */
class DayWidget : AppWidgetProvider() {
    override fun onUpdate(ctx: Context, manager: AppWidgetManager, ids: IntArray) = Widgets.updateAll(ctx)

    override fun onDisabled(ctx: Context) = Widgets.updateAll(ctx)
}

/** Будильник пересчёта «через N мин». */
class WidgetTickReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action == ACTION) Widgets.updateAll(ctx)
    }

    companion object {
        const val ACTION = "ru.uiboshki.app.widget.TICK"
    }
}
