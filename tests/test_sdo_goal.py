"""Цель по предмету (sdo_goal.py): сколько не хватает до зачёта/«3»/«4»/«5»,
откуда взять (открытые работы, посещения впереди), правило 75 % зачтённых
работ ТК и «что если пропущу лекцию». Без дат: когда делать — решает человек."""
import pytest

import sdo_goal

EXAM = [{"at": 40, "label": "3"}, {"at": 60, "label": "4"}, {"at": 80, "label": "5"}]


def course(score, works, marks=EXAM, exam=0):
    """exam — сколько ещё можно взять на экзамене (по умолчанию уже сдан)."""
    return {"id": 7, "score": score, "marks": marks, "pass_share": 0.75,
            "categories": [{"name": "Семестровый контроль", "score": 40 - exam, "max": 40}],
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


def test_exam_points_count_toward_goal():
    """Баг 09.10 (владелец): «на 5 не хватит — будет 62 < 80», хотя пороги —
    по сумме с экзаменом, а на нём ещё до 40."""
    c = course(10, [("ok", 3), ("ok", 3), ("ok", 4), ("todo", 42)], exam=40)
    g = sdo_goal.plan(c, {"ok": True, "can_get": 12.5}, "5")
    assert g["exam_left"] == 40 and g["best"] == 104.5 and g["status"] == "ok"
    # без экзамена было бы 64,5 — «не хватит»; без категории в журнале — 40 по умолчанию
    no_cat = dict(c, categories=[])
    assert sdo_goal.plan(no_cat, None, "5")["exam_left"] == 40
    # у зачёта экзамена нет
    credit = course(10, [("todo", 20)], marks=[{"at": 40, "label": "зачёт"}], exam=40)
    assert sdo_goal.plan(credit, None)["exam_left"] == 0


def test_final_mark_rules():
    """Правила БРС владельца (09.10): итог = семестр + экзамен, минимума на
    экзамене нет; автомат — «3» и «4», «5» автоматом не бывает, автомат —
    только при 75 % зачтённых работ."""
    assert sdo_goal.final_mark(EXAM, 59, 1) == "4"                  # 59 + 1 балл на экзамене
    assert sdo_goal.final_mark(EXAM, 59, None) == "3"               # без экзамена — «3» автоматом
    assert sdo_goal.final_mark(EXAM, 60, None, tk_ok=True) == "4"
    assert sdo_goal.final_mark(EXAM, 85, None, tk_ok=True) == "4"   # «5» автоматом нет
    assert sdo_goal.final_mark(EXAM, 85, 0) == "5"                  # с экзаменом — по сумме
    assert sdo_goal.final_mark(EXAM, 60, None, tk_ok=False) is None  # работы не зачтены — автомата нет
    assert sdo_goal.final_mark(EXAM, 30, None) is None
    credit = [{"at": 40, "label": "зачёт"}]
    assert sdo_goal.final_mark(credit, 41, None) == "зачёт"


ALL_OK = [("ok", 5)] * 4


def test_auto_and_exam_in_goal():
    # 60 и зачтено 75 % — «4» автоматом, цель «4» есть
    g = sdo_goal.plan(course(60, ALL_OK, exam=40), None, "4")
    assert g["exam_pending"] and g["auto"] == "4" and g["status"] == "done" and g["need_exam"] == 0
    # на «5» — 20 баллов на экзамене, «4» уже автоматом
    g = sdo_goal.plan(course(60, ALL_OK, exam=40), None, "5")
    assert (g["auto"], g["need_exam"], g["exam_max"], g["status"]) == ("4", 20, 40, "ok")
    assert not g["auto_ok"]
    # 85 без экзамена — всё равно не «5»: «есть» не бывает, на экзамен идти (минимума нет)
    g = sdo_goal.plan(course(85, ALL_OK, exam=40), None, "5")
    assert g["auto"] == "4" and g["need_exam"] == 0 and g["status"] != "done"
    # 59: «3» автоматом, на «4» — 1 балл на экзамене
    g = sdo_goal.plan(course(59, ALL_OK, exam=40), None, "4")
    assert (g["auto"], g["need_exam"], g["status"]) == ("3", 1, "ok")
    # работы не зачтены — автомата нет, хоть баллов и хватает; добрать можно
    g = sdo_goal.plan(course(60, [("ok", 5), ("ok", 5), ("todo", 5), ("todo", 5)], exam=40), None, "4")
    assert g["auto"] is None and g["auto_best"] == "4" and g["status"] != "done"
    # даже с полным экзаменом не хватает — «не хватит», и на сколько
    g = sdo_goal.plan(course(30, ALL_OK, exam=40), None, "5")
    assert (g["need_exam"], g["exam_short"], g["status"]) == (40, 10, "no")
    # экзамен уже сдан — по сумме, без автомата
    g = sdo_goal.plan(course(85, ALL_OK), None, "5")
    assert not g["exam_pending"] and g["auto"] is None and g["status"] == "done"
    # у зачёта экзамена нет — как раньше
    g = sdo_goal.plan(course(45, ALL_OK, marks=[{"at": 40, "label": "зачёт"}], exam=40), None)
    assert not g["exam_pending"] and g["status"] == "done" and g["exam_left"] == 0


@pytest.mark.asyncio
async def test_goals_saved_per_user(db):
    assert await sdo_goal.get_goals(1) == {}
    await sdo_goal.set_goal(1, 7, "4")
    await sdo_goal.set_goal(1, 8, "зачёт")
    await sdo_goal.set_goal(1, 8, None)
    assert await sdo_goal.get_goals(1) == {"7": "4"} and await sdo_goal.get_goals(2) == {}
