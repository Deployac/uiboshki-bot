"""
Сдал в СДО — дедлайн у себя отмечен сам.

Раньше отметку «сдал» ставил только сам человек: сдал работу прямо из бота
или увидел в журнале «отправлено» — а дедлайн висит, и напоминания идут.
Теперь бот ставит её сам, у каждого свою (deadline_done):
  • сразу после сдачи через бота (/api/sdo/submit);
  • когда человек открыл предмет в СДО, а там задание зачтено («ok») или
    сдано и ждёт оценки («wait»).
Снимать отметку бот не снимает никогда: «не сдано» в журнале бывает и по
ошибке СДО, а убрать галочку человек всегда может сам.
"""

import logging
import re

logger = logging.getLogger(__name__)

# ссылка на задание или тест в описании дедлайна из СДО
CMID_RE = re.compile(r"/mod/(?:assign|quiz)/view\.php\?(?:[^#\s\"']*&)?id=(\d+)")
DONE_STATUSES = ("ok", "wait")


def cmid_of(text: str) -> int | None:
    m = CMID_RE.search(text or "")
    return int(m.group(1)) if m else None


async def mark(user_id: int, cmids) -> int:
    """Отметить сданными дедлайны с этими заданиями (cmid). → сколько отмечено."""
    from database import get_active_deadlines, set_deadline_done
    cmids = {int(c) for c in cmids if c}
    if not cmids:
        return 0
    n = 0
    for d in await get_active_deadlines(user_id):
        if not d.get("done") and cmid_of(d.get("description")) in cmids:
            await set_deadline_done(d["id"], user_id, True)
            n += 1
    if n:
        logger.info(f"СДО: {user_id} — {n} дедлайн(ов) отмечено сданными по журналу")
    return n


def finished(course: dict) -> list[int]:
    """cmid заданий курса, которые в журнале зачтены или ждут оценки."""
    return [w["cmid"] for w in course.get("works") or []
            if w.get("cmid") and w.get("status") in DONE_STATUSES]
