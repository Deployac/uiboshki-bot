"""
Новые задания из СДО и перенесённые сроки — всем, у кого включено
(уведомления → «Новые задания»).

Синк СДО (scheduler.sync_sdo_deadlines, раз в 6 ч) раньше писал только
старосте «добавлено N». Теперь каждому — одно сообщение на синк со списком:
что появилось и до когда. Показываем только то, что человек видит у себя в
дедлайнах (get_active_deadlines, свои отметки) и без предметов по выбору,
куда человек не ходит (OPTIONAL_SUBJECTS без ответа «хожу»), а
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


def _was(iso: str) -> str:
    from schedule_parser import MONTHS_GEN
    d = date.fromisoformat(iso)
    return f"{d.day} {MONTHS_GEN[d.month - 1]}"


def _lines(items: list[dict]) -> list[str]:
    from utils import esc
    return [f"• <b>{esc(i['subject'])}</b> — " + ("теперь " if i.get("was") else "")
            + when(i["due_date"], i.get("due_time"))
            + (f" (было {_was(i['was'])})" if i.get("was") and i["was"] != i["due_date"] else "")
            for i in sorted(items, key=lambda i: (i["due_date"], i.get("due_time") or ""))]


def build(items: list[dict], moved: list[dict] | None = None) -> str:
    """Новые задания и перенесённые сроки — одним сообщением."""
    parts = []
    if items:
        head = "🆕 В СДО новое задание:" if len(items) == 1 else "🆕 В СДО новые задания:"
        parts.append(head + "\n" + "\n".join(_lines(items)))
    if moved:
        head = "📅 Срок перенесли:" if len(moved) == 1 else "📅 Сроки перенесли:"
        parts.append(head + "\n" + "\n".join(_lines(moved)))
    return "\n\n".join(parts)


async def announce(bot, new_ids: list[int], moved: dict[int, str] | None = None) -> int:
    """Разослать про новые дедлайны и перенесённые сроки (из синка). → скольким ушло."""
    import notify_prefs
    from database import get_active_deadlines, get_reminder_users
    from keyboards import app_button
    moved = moved or {}
    if len(new_ids) > MASS:
        logger.info(f"новые задания: {len(new_ids)} за раз — не рассылаю (выгрузка, а не новое)")
        new_ids = []
    if len(moved) > MASS:
        logger.info(f"перенесённые сроки: {len(moved)} за раз — не рассылаю")
        moved = {}
    if not new_ids and not moved:
        return 0
    from config import OPTIONAL_SUBJECTS
    from database import get_all_optional_answers
    answers = await get_all_optional_answers()
    ids, sent = set(new_ids), 0
    for user in await get_reminder_users():
        uid = user["user_id"]
        if not notify_prefs.merge(user.get("notify")).get("new_tasks"):
            continue
        # предметы по выбору, куда человек не ходит («хожу» не отвечал), — мимо
        skip = [s.lower() for s in OPTIONAL_SUBJECTS if not answers.get(uid, {}).get(s)]
        visible = [d for d in await get_active_deadlines(uid) if not d.get("done")
                   and not any(s in (d.get("subject") or "").lower() for s in skip)]
        mine = [d for d in visible if d["id"] in ids]
        shifted = [dict(d, was=moved[d["id"]]) for d in visible if d["id"] in moved]
        if not mine and not shifted:
            continue
        try:
            import delivery
            await delivery.deliver(bot, uid, build(mine, shifted), kind="new_tasks", tab="deadlines",
                                   reply_markup=app_button("📋 Открыть дедлайны", "deadlines"))
            sent += 1
        except Exception as e:
            logger.info(f"новые задания {uid}: {e}")
    return sent
