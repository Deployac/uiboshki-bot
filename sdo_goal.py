"""
Цель по предмету: что нужно, чтобы дойти до зачёта, «3», «4» или «5».

Не расписание и не план по дням — когда делать, человек решает сам
(владелец: «люди делают в тот день, когда есть настроение»). Бот только
считает:
  • сколько баллов не хватает до выбранной оценки и откуда их взять —
    открытые работы текущего контроля (их максимум) и посещения лекций
    впереди (attendance.py);
  • правило БРС: зачтено не меньше 75 % работ ТК. Зачтена — оценка не ниже
    проходного порога со страницы работы в СДО. Меньше 75 % — экзамена по
    БРС не будет, и баллы почти ничего не решают;
  • итог: «есть», «дойдёшь», «впритык» или «не хватит, даже если сдать всё».

Работы ниже порога («low») и с прошедшим сроком («miss») считаем
потерянными: пересдачу открывает преподаватель, на неё не рассчитываем.
Своя цель хранится в settings («goals:<id>» → {курс: оценка}); без неё —
первая отметка курса (зачёт или «3»).
"""

import json
import math

OPEN = ("todo", "soon", "offline", "wait")    # ещё могут дать баллы и зачёт
LOST = ("low", "miss")
TIGHT_MARGIN = 5.0                            # запас меньше — «впритык»


async def get_goals(user_id: int) -> dict[str, str]:
    from database import get_setting
    try:
        data = json.loads(await get_setting(f"goals:{user_id}") or "{}")
    except ValueError:
        return {}
    return {str(k): str(v) for k, v in data.items()} if isinstance(data, dict) else {}


async def set_goal(user_id: int, course_id: int, label: str | None) -> dict[str, str]:
    from database import set_setting
    goals = await get_goals(user_id)
    if label:
        goals[str(course_id)] = label
    else:
        goals.pop(str(course_id), None)
    await set_setting(f"goals:{user_id}", json.dumps(goals, ensure_ascii=False))
    return goals


def _status(score: float, at: float, best: float, tk: dict) -> str:
    if score >= at and tk["ok"]:
        return "done"
    if best < at or not tk["reachable"]:
        return "no"
    if best - at < TIGHT_MARGIN or (tk["left"] and tk["left"] >= tk["open"]):
        return "tight"          # мало запаса по баллам или зачесть нужно все открытые
    return "ok"


def plan(course: dict, attendance: dict | None = None, label: str | None = None) -> dict:
    """course — ответ sdo_grades.course_detail (работы со статусами),
    attendance — attendance.for_course или None."""
    marks = course.get("marks") or [{"at": 40, "label": "3"}]
    mark = next((m for m in marks if m["label"] == label), marks[0])
    at, score = float(mark["at"]), float(course.get("score") or 0)
    works = course.get("works") or []
    open_ = [w for w in works if w.get("status") in OPEN]
    lost = [w for w in works if w.get("status") in LOST]
    open_points = sum(float(w.get("max") or 0) for w in open_)
    att_ok = bool(attendance and attendance.get("ok"))
    att_left = float(attendance.get("can_get") or 0) if att_ok else 0.0
    best = score + open_points + att_left

    total = len(works)
    passed = sum(1 for w in works if w.get("status") == "ok")
    need = math.ceil(total * float(course.get("pass_share") or 0.75)) if total else 0
    left = max(0, need - passed)
    tk = {"total": total, "passed": passed, "need": need, "left": left, "open": len(open_),
          "ok": passed >= need, "reachable": len(open_) >= left}

    out = {
        "label": mark["label"], "at": at, "own": bool(label) and mark["label"] == label,
        "marks": [m["label"] for m in marks],
        "score": round(score, 2), "need": round(max(0.0, at - score), 2),
        "open_points": round(open_points, 2), "open_count": len(open_),
        "attendance_left": round(att_left, 2), "best": round(best, 2),
        "lost_count": len(lost), "lost_points": round(sum(float(w.get("max") or 0) for w in lost), 2),
        "tk": tk, "status": _status(score, at, best, tk),
    }
    # «что если пропущу лекцию»: минус одна лекция из того, что дают посещения
    future = [x for x in (attendance or {}).get("lectures") or [] if x.get("status") == "future"]
    if att_ok and future and attendance.get("unit"):
        unit = min(float(attendance["unit"]), att_left)
        out["skip"] = {"value": round(unit, 2), "date": future[0]["date"],
                       "status": _status(score, at, best - unit, tk)}
    return out
