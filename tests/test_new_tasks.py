"""Новые задания из СДО — каждому, у кого включено (new_tasks.py)."""
import pytest

import new_tasks


class FakeBot:
    def __init__(self):
        self.sent = []

    async def send_message(self, chat_id, text, **kw):
        self.sent.append((chat_id, text))


def test_build_text():
    text = new_tasks.build([{"subject": "Практика 3 · Анализ данных", "due_date": "2026-10-08", "due_time": "23:59"},
                            {"subject": "Тест <2>", "due_date": "2026-10-07", "due_time": None}])
    assert text.startswith("🆕 В СДО новые задания:")
    assert text.index("Тест &lt;2&gt;") < text.index("Практика 3")                     # по сроку
    assert "чт, 8 октября до 23:59" in text and "ср, 7 октября" in text


@pytest.mark.asyncio
async def test_announce_respects_prefs_done_and_mass(db):
    for uid in (1, 2, 3):
        await db.upsert_user(uid, "", "")
    await db.set_notify(2, {"new_tasks": False})                                     # выключил
    await db.upsert_user(4, "", "")
    await db.set_subscription(4, 0)                                                  # отписан от всего
    d1 = await db.add_deadline("Практика 3 · Анализ данных", "", "2026-10-08", "23:59", 0, external_id="sdo:1")
    d2 = await db.add_deadline("Тест 2 · Учётная деятельность", "", "2026-10-09", None, 0, external_id="sdo:2")
    await db.mark_deadline_done(d2, 3)                                               # уже сдал
    bot = FakeBot()
    assert await new_tasks.announce(bot, [d1, d2]) == 2
    got = dict(bot.sent)
    assert set(got) == {1, 3}
    assert "Практика 3" in got[3] and "Тест 2" not in got[3]
    assert "Практика 3" in got[1] and "Тест 2" in got[1]
    bot = FakeBot()
    assert await new_tasks.announce(bot, list(range(1, new_tasks.MASS + 2))) == 0 and not bot.sent   # выгрузка всего
    assert await new_tasks.announce(bot, []) == 0
