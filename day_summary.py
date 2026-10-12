"""
«Итоги дня» на прошедших днях недели (второй круг дизайна, варианты А+Г):
что человек сдал в этот день (отметки deadline_done) и сколько баллов СДО
прибавилось (история sdo_score_history). Пустой день — None: карточки нет.
"""

import json
from datetime import date, datetime, time, timedelta, timezone

import aiosqlite

from utils import TZ

NAMES_KEY = "sdo_course_names"   # общий словарь {курс: название} в settings
MAX_DONE = 6
MIN_DELTA = 0.05


async def remember_courses(courses: list[dict]):
    """Дописать названия курсов в общий словарь (не затирая чужие)."""
    names = {str(c["id"]): (c.get("title") or c.get("name") or "").strip()
             for c in courses if c.get("id") is not None}
    names = {k: v for k, v in names.items() if v}
    if not names:
        return
    import locks
    from database import get_setting, set_setting
    async with locks.lock("settings", NAMES_KEY):
        try:
            cur = json.loads(await get_setting(NAMES_KEY) or "{}")
        except ValueError:
            cur = {}
        if all(cur.get(k) == v for k, v in names.items()):
            return
        cur.update(names)
        await set_setting(NAMES_KEY, json.dumps(cur, ensure_ascii=False))


async def _course_names() -> dict[str, str]:
    from database import get_setting
    try:
        return json.loads(await get_setting(NAMES_KEY) or "{}")
    except ValueError:
        return {}


def _utc_bounds(d: date) -> tuple[str, str]:
    """Сутки по Москве → полуинтервал в UTC, как пишет datetime('now')."""
    fmt = "%Y-%m-%d %H:%M:%S"
    start = datetime.combine(d, time(), TZ).astimezone(timezone.utc)
    end = datetime.combine(d + timedelta(days=1), time(), TZ).astimezone(timezone.utc)
    return start.strftime(fmt), end.strftime(fmt)


async def _done(user_id: int, d: date) -> list[dict]:
    from database._conn import connect
    from database.deadlines import get_deadline_mine
    lo, hi = _utc_bounds(d)
    async with connect() as db:
        db.row_factory = aiosqlite.Row
        rows = await (await db.execute(
            "SELECT d.id, d.subject FROM deadline_done x JOIN deadlines d ON d.id = x.deadline_id "
            "WHERE x.user_id = ? AND x.done_at >= ? AND x.done_at < ? ORDER BY x.done_at",
            (user_id, lo, hi))).fetchall()
    mine = await get_deadline_mine(user_id) if rows else {}
    out = []
    for r in rows:
        m = mine.get(r["id"]) or {}
        if m.get("hidden"):          # убрал у себя — и в итогах нет
            continue
        out.append({"title": m.get("subject") or r["subject"]})   # своя правка — как в /api/deadlines
    return out[:MAX_DONE]


async def _grades(user_id: int, d: date) -> list[dict]:
    from database._conn import connect
    day = d.isoformat()
    async with connect() as db:
        rows = await (await db.execute(
            "SELECT h.course_id, h.score, "
            "(SELECT p.score FROM sdo_score_history p WHERE p.user_id = h.user_id "
            " AND p.course_id = h.course_id AND p.day < h.day ORDER BY p.day DESC LIMIT 1) "
            "FROM sdo_score_history h WHERE h.user_id = ? AND h.day = ? ORDER BY h.course_id",
            (user_id, day))).fetchall()
    out = []
    names = None
    for cid, score, prev in rows:
        if prev is None or abs(score - prev) < MIN_DELTA:   # нет прошлой точки — прирост не знаем
            continue
        if names is None:
            names = await _course_names()
        out.append({"name": names.get(str(cid)) or "Предмет", "delta": round(score - prev, 1)})
    return out


async def summary(user_id: int, d: date) -> dict | None:
    """{"done": [{"title"}], "grades": [{"name", "delta"}], "points"} или None."""
    done = await _done(user_id, d)
    grades = await _grades(user_id, d)
    if not done and not grades:
        return None
    return {"done": done, "grades": grades, "points": round(sum(g["delta"] for g in grades), 1)}
