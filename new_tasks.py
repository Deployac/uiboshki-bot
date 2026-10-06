"""
Новые задания из СДО — всем, у кого включено (уведомления → «Новые задания»).

Синк СДО (scheduler.sync_sdo_deadlines, раз в 6 ч) раньше писал только
старосте «добавлено N». Теперь каждому — одно сообщение на синк со списком:
что появилось и до когда. Показываем только то, что человек видит у себя в
дедлайнах (get_active_deadlines: предметы по выбору, свои отметки), а
массовый завал — начало семестра, первый синк, СДО отдал всё разом — не
рассылаем: это не «новое», а «всё».
"""

import logging
from datetime import date

logger = logging.getLogger(__name__)

MASS = 8            # больше за один синк — это не новые задания, а выгрузка всего
WEEKDAYS = ["пн", "вт", "ср", "чт", "пт", "сб", "вс"]


def when(due_date: str, due_time: str | None) -> str:
    """«чт, 8 октября до 23:59»."""
    from schedule_parser import MONTHS_GEN
    d = date.fromisoformat(due_date)
    text = f"{WEEKDAYS[d.weekday()]}, {d.day} {MONTHS_GEN[d.month - 1]}"
    return text + (f" до {due_time}" if due_time else "")


def build(items: list[dict]) -> str:
    from utils import esc
    head = "🆕 В СДО новое задание:" if len(items) == 1 else "🆕 В СДО новые задания:"
    lines = [f"• <b>{esc(i['subject'])}</b> — {when(i['due_date'], i.get('due_time'))}"
             for i in sorted(items, key=lambda i: (i["due_date"], i.get("due_time") or ""))]
    return head + "\n" + "\n".join(lines)


async def announce(bot, new_ids: list[int]) -> int:
    """Разослать про новые дедлайны (id из синка). → скольким ушло."""
    import notify_prefs
    from database import get_active_deadlines, get_reminder_users
    from keyboards import app_button
    if not new_ids:
        return 0
    if len(new_ids) > MASS:
        logger.info(f"новые задания: {len(new_ids)} за раз — не рассылаю (выгрузка, а не новое)")
        return 0
    ids, sent = set(new_ids), 0
    for user in await get_reminder_users():
        uid = user["user_id"]
        if not notify_prefs.merge(user.get("notify")).get("new_tasks"):
            continue
        mine = [d for d in await get_active_deadlines(uid) if d["id"] in ids and not d.get("done")]
        if not mine:
            continue
        try:
            await bot.send_message(uid, build(mine), parse_mode="HTML",
                                   reply_markup=app_button("📋 Открыть дедлайны", "deadlines"))
            sent += 1
        except Exception as e:
            logger.info(f"новые задания {uid}: {e}")
    return sent
