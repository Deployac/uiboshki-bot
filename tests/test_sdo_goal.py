"""Цель по предмету (sdo_goal.py): сколько не хватает до зачёта/«3»/«4»/«5»,
откуда взять (открытые работы, посещения впереди), правило 75 % зачтённых
работ ТК и «что если пропущу лекцию». Без дат: когда делать — решает человек."""
import pytest

import sdo_goal

EXAM = [{"at": 40, "label": "3"}, {"at": 60, "label": "4"}, {"at": 80, "label": "5"}]


def course(score, works, marks=EXAM):
    return {"id": 7, "score": score, "marks": marks, "pass_share": 0.75,
            "works": [{"name": f"Работа {i}", "max": mx, "status": st} for i, (st, mx) in enumerate(works)]}


ATT = {"ok": True, "can_get": 5.0, "unit": 2.5,
       "lectures": [{"date": "2026-10-01", "status": "ok"}, {"date": "2026-10-15", "status": "future"}]}


def test_default_goal_is_first_mark_and_counts_sources():
    c = course(30, [("ok", 5), ("ok", 5), ("ok", 5), ("todo", 8), ("soon", 6)])
    g = sdo_goal.plan(c, ATT)
    assert (g["label"], g["at"], g["need"], g["own"]) == ("3", 40, 10, False)
    assert (g["open_points"], g["open_count"], g["attendance_left"], g["best"]) == (14, 2, 5, 49)
    assert g["tk"] == {"total": 5, "passed": 3, "need": 4, "left": 1, "open": 2, "ok": False, "reachable": True}
    assert g["status"] == "ok"
    assert g["skip"] == {"value": 2.5, "date": "2026-10-15", "status": "ok"}


def test_own_goal_tight_and_no():
    c = course(48, [("ok", 5), ("ok", 5), ("ok", 5), ("todo", 8)])
    g = sdo_goal.plan(c, ATT, "4")
    assert g["own"] and g["need"] == 12 and g["best"] == 61 and g["status"] == "tight"   # запас 1 < 5
    assert g["skip"]["status"] == "no"                      # без лекции «4» уже не набрать
    g = sdo_goal.plan(c, ATT, "5")
    assert g["status"] == "no" and g["best"] < g["at"]
    assert sdo_goal.plan(c, ATT, "нет такой")["label"] == "3"                          # неизвестная — первая


def test_tk_rule_lost_works_and_done():
    # ниже порога и просроченные не считаются: зачесть 3 из 4 уже нельзя
    c = course(45, [("ok", 5), ("low", 5), ("miss", 5), ("todo", 5)])
    g = sdo_goal.plan(c, None)
    assert g["tk"]["left"] == 2 and not g["tk"]["reachable"] and g["status"] == "no"
    assert g["lost_count"] == 2 and g["lost_points"] == 10 and "skip" not in g
    # баллы есть и 75 % есть — «есть»; ждёт оценки — тоже открытая работа
    done = sdo_goal.plan(course(45, [("ok", 5), ("ok", 5), ("ok", 5), ("wait", 5)]), None)
    assert done["status"] == "done" and done["open_count"] == 1
    # всё сдано и зачтено — впритык не бывает, даже без запаса
    assert sdo_goal.plan(course(41, [("ok", 5)]), None)["status"] == "done"
    # зачесть нужно все оставшиеся — «впритык», хоть баллов и с запасом
    assert sdo_goal.plan(course(30, [("ok", 9), ("low", 9), ("todo", 9), ("todo", 9)]), ATT)["status"] == "tight"


@pytest.mark.asyncio
async def test_goals_saved_per_user(db):
    assert await sdo_goal.get_goals(1) == {}
    await sdo_goal.set_goal(1, 7, "4")
    await sdo_goal.set_goal(1, 8, "зачёт")
    await sdo_goal.set_goal(1, 8, None)
    assert await sdo_goal.get_goals(1) == {"7": "4"} and await sdo_goal.get_goals(2) == {}
