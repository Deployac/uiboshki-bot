"""
Обзор недели — в воскресенье вечером (тумблер «Обзор недели» в
уведомлениях, notify_prefs: weekly). Одним сообщением: номер недели, пары по
дням (во сколько первая, где — если не в своём корпусе), свободные дни и
дедлайны на неделе. Пар и дедлайнов нет — не шлём. Предметы по выбору — как
у человека (optional_subjects).
"""

import logging
from datetime import date, datetime, timedelta

from utils import TZ, esc

logger = logging.getLogger(__name__)
DAYS = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
MAX_DEADLINES = 6


def next_monday(today: date) -> date:
    return today + timedelta(days=(7 - today.weekday()) % 7 or 7)


def build(raw: bytes, monday: date, deadlines: list[dict], home: str | None) -> str | None:
    """Текст обзора недели, начинающейся с monday; None — неделя пустая."""
    import notify_prefs
    from schedule_parser import MONTHS_GEN, lessons_for_date, week_number
    lines, total, free = [], 0, []
    for i in range(6):
        d = monday + timedelta(days=i)
        lessons = lessons_for_date(raw, d)
        pairs = sum(l["pairs"] for l in lessons)
        if not pairs:
            free.append(DAYS[i])
            continue
        total += pairs
        campuses = sorted({c for c in (notify_prefs.campus_of(l["room"]) for l in lessons) if c and c != home})
        where = f" · 📍 {', '.join(campuses)}" if campuses else ""
        word = "пара" if pairs == 1 else ("пары" if pairs < 5 else "пар")
        lines.append(f"<b>{DAYS[i]}</b> — {pairs} {word}, с {lessons[0]['start']}{where}")
    week_dl = [d for d in deadlines if not d.get("done")
               and monday.isoformat() <= d["due_date"] <= (monday + timedelta(days=6)).isoformat()]
    if not total and not week_dl:
        return None
    num = week_number(raw, monday)
    sunday = monday + timedelta(days=6)
    span = (f"{monday.day}–{sunday.day} {MONTHS_GEN[sunday.month - 1]}" if monday.month == sunday.month
            else f"{monday.day} {MONTHS_GEN[monday.month - 1]} – {sunday.day} {MONTHS_GEN[sunday.month - 1]}")
    out = [f"🗓 <b>Неделя{f' {num}' if num else ''}</b> · {span}"]
    if total:
        out.append(f"Всего пар: <b>{total}</b>" + (f" · свободно: {', '.join(free)}" if free else ""))
        out += lines
    else:
        out.append("Пар на неделе нет 🎉")
    if week_dl:
        out.append("\n⏳ <b>Сдать на неделе</b>")
        for d in sorted(week_dl, key=lambda x: (x["due_date"], x.get("due_time") or "99"))[:MAX_DEADLINES]:
            day = DAYS[date.fromisoformat(d["due_date"]).weekday()]
            out.append(f"• {esc(d['subject'])} — {day}{' ' + d['due_time'] if d.get('due_time') else ''}")
        if len(week_dl) > MAX_DEADLINES:
            out.append(f"…и ещё {len(week_dl) - MAX_DEADLINES}")
    return "\n".join(out)


async def send_all(bot, now: datetime | None = None):
    """Воскресенье вечером: обзор следующей недели каждому, у кого включено."""
    import notify_prefs
    from config import OPTIONAL_SUBJECTS
    from database import get_active_deadlines, get_all_optional_answers, get_reminder_users
    from keyboards import app_button
    from optional_subjects import HIDE
    from schedule_parser import fetch_schedule_raw
    now = now or datetime.now(TZ)
    monday = next_monday(now.date())
    try:
        raw = await fetch_schedule_raw()
    except Exception as e:
        logger.warning(f"обзор недели: нет расписания: {e}")
        return
    home = notify_prefs.home_campus(raw)
    answers = await get_all_optional_answers()
    for user in await get_reminder_users():
        uid = user["user_id"]
        if not notify_prefs.merge(user.get("notify")).get("weekly"):
            continue
        token = HIDE.set(frozenset(s for s in OPTIONAL_SUBJECTS if not answers.get(uid, {}).get(s)))
        try:
            text = build(raw, monday, await get_active_deadlines(uid), home)
        finally:
            HIDE.reset(token)
        if not text:
            continue
        try:
            await bot.send_message(uid, text, parse_mode="HTML", reply_markup=app_button("📅 Открыть неделю", "today"))
        except Exception as e:
            logger.info(f"обзор недели {uid}: {e}")
