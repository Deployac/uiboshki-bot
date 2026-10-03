"""Новые баллы в СДО: сравнение с последней точкой истории, первый раз —
молча, сообщение со всеми изменившимися предметами, тумблер в уведомлениях."""
import pytest

import grade_alerts


def test_changes_only_with_history():
    courses = [{"id": 1, "name": "Модел", "score": 39}, {"id": 2, "name": "ООП", "score": 10},
               {"id": 3, "name": "Матан", "score": 5}, {"id": 4, "name": "Без", "score": None}]
    diff = grade_alerts.changes({1: 34.0, 2: 10.0}, courses)
    assert [(c["id"], o, n) for c, o, n in diff] == [(1, 34.0, 39.0)]


def test_message_signs():
    text = grade_alerts.message([({"name": "Модел"}, 34.0, 39.0), ({"name": "А<б"}, 12.5, 10.0)])
    assert "Модел: 34 → <b>39</b> (+5)" in text
    assert "А&lt;б: 12.5 → <b>10</b> (-2.5)" in text


@pytest.mark.asyncio
async def test_check_all(db, monkeypatch):
    import sdo_accounts
    import sdo_grades
    for uid in (1, 2, 3):
        await db.upsert_user(uid, "", "X")
        await db.save_sdo_session(uid, sdo_accounts.encrypt(f"c{uid}"))
    await db.set_notify(3, {"grades": False})
    await db.save_score_points(1, "2026-09-20", {7: 30.0})
    await db.save_score_points(1, "2026-09-24", {7: 34.0})
    scores = {1: 39, 2: 50, 3: 1}

    async def overview(uid, cookie, fresh=False):
        assert fresh and cookie == f"c{uid}"
        return {"courses": [{"id": 7, "name": "Моделирование", "score": scores[uid]}]}

    monkeypatch.setattr(sdo_grades, "overview", overview)
    sent = []

    class Bot:
        async def send_message(self, uid, text, **kw):
            sent.append((uid, text))

    await grade_alerts.check_all(Bot(), pause=0)
    assert [u for u, _ in sent] == [1]                       # 2 — первый раз, 3 — выключено
    assert "34 → <b>39</b> (+5)" in sent[0][1]
    assert await db.get_last_scores(2) == {7: 50.0}           # запомнили для следующего раза
    assert await db.get_last_scores(3) == {7: 1.0}            # тумблер выключен — сообщения нет, а точка
                                                              # истории есть: по ней считаются посещения
    sent.clear()
    await grade_alerts.check_all(Bot(), pause=0)
    assert sent == []                                         # не изменилось — тишина


def test_toggle_in_app():
    import notify_prefs
    assert notify_prefs.merge(None)["grades"] is True
    assert "toggleNotify('grades')" in open("webapp/static/js/more.js", encoding="utf-8").read()
