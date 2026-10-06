"""/status у старосты (health.py): СДО, расписание, бэкап, ошибки за сутки."""
import logging
import time

import pytest

import health


def test_areas_and_version():
    assert health.area_of("ai_solver") == "ИИ" and health.area_of("webapp.routes.chat") == "ИИ"
    assert health.area_of("sdo_parser") == "СДО" and health.area_of("schedule_parser") == "Расписание"
    assert health.area_of("handlers.files") == "Прочее"
    assert health.version().startswith("v5.")


def test_error_counter_by_area(monkeypatch):
    c = health.ErrorCounter()
    log = logging.getLogger("gemini_solver")
    log.addHandler(c)
    try:
        log.error("лимит запросов")
        log.warning("медленно")
        logging.getLogger("gemini_solver").info("не считается")
    finally:
        log.removeHandler(c)
    day = c.last_day()
    assert [(lvl, area) for _, lvl, area, _ in day] == [(logging.ERROR, "ИИ"), (logging.WARNING, "ИИ")]
    c.records.append((time.time() - 2 * health.DAY, logging.ERROR, "СДО", "старое"))
    assert len(c.last_day()) == 2                      # старше суток — не в отчёте


@pytest.mark.asyncio
async def test_report_shows_notes_and_errors(db, monkeypatch):
    import config
    monkeypatch.setattr(config, "SDO_SESSION_COOKIE", "x")
    monkeypatch.setattr(health, "counter", health.ErrorCounter())
    await health.note("sdo_cookie", True)          # на свежей базе отметка не теряется
    assert "✅ Кука жива — сегодня" in await health.report()
    await health.note("sdo_cookie", False, "")
    text = await health.report()
    assert "Синк дедлайнов — ещё не было" in text and "Ни одной" in text

    await health.note("sdo_cookie", True)
    await health.note("sdo_sync", False, "кука протухла")
    await health.note("backup", True, "3.2 МБ")
    health.counter.records.append((time.time(), logging.ERROR, "ИИ", "Gemini <лимит>"))
    text = await health.report()
    assert "✅ Кука жива — сегодня" in text
    assert "⚠️ Синк дедлайнов — сегодня" in text and "кука протухла" in text
    assert "✅ Копия базы — сегодня" in text and "3.2 МБ" in text
    assert "❌ Ошибки: ИИ 1" in text and "Gemini &lt;лимит&gt;" in text


@pytest.mark.asyncio
async def test_status_only_for_starosta(db):
    from aiogram import Bot, Dispatcher
    from aiogram.fsm.storage.memory import MemoryStorage
    from aiogram.types import Chat, Message, Update, User
    from handlers import announce
    from tests.conftest import STAROSTA_ID
    from tests.test_solver_render import RecordingSession
    bot = Bot(token="123456:TEST-TOKEN-NOT-REAL-AAAAAAAAAAAAAAAAAAA", session=RecordingSession())
    dp = Dispatcher(storage=MemoryStorage())
    dp.include_router(announce.router)
    try:
        for i, uid in enumerate((222, STAROSTA_ID)):
            u = User(id=uid, is_bot=False, first_name="X")
            msg = Message(message_id=i + 1, date=0, chat=Chat(id=uid, type="private"), from_user=u, text="/status")
            await dp.feed_update(bot, Update(update_id=int(time.time()) + i, message=msg))
    finally:
        announce.router._parent_router = None
    sent = [t for t, _ in bot.session.sent if "Состояние бота" in t]
    assert len(sent) == 1


def test_error_spike_alert(monkeypatch):
    """Всплеск ошибок — старосте сам: ≥5 ERROR за час, не чаще раза в 3 часа;
    предупреждения и старые ошибки не считаются."""
    import logging
    import health
    monkeypatch.setattr(health, "_alerted_at", 0.0)
    monkeypatch.setattr(health.counter, "records", health.deque(maxlen=2000))
    now = 1_000_000.0
    rec = health.counter.records
    for i in range(4):
        rec.append((now - 60 * i, logging.ERROR, "СДО", f"синк упал {i}"))
    rec.append((now - 7200, logging.ERROR, "ИИ", "давно"))              # старше часа
    rec.append((now - 10, logging.WARNING, "ИИ", "предупреждение"))
    assert health.error_spike(now) is None                               # 4 — ещё не повод
    rec.append((now - 5, logging.ERROR, "ИИ", "Gemini <429>"))
    text = health.error_spike(now)
    assert text.startswith("⚠️ <b>За час 5 ошибок</b>: СДО — 4 · ИИ — 1")
    assert "Gemini &lt;429&gt;" in text
    assert health.error_spike(now + 600) is None                         # через 10 минут — не повторяем
    assert health.error_spike(now + 3 * 3600 + 1) is None                # ошибки уже старые


@pytest.mark.asyncio
async def test_report_ai_section(db, monkeypatch):
    """/status: вопросы ИИ сегодня и «основная модель отдыхает — отвечают запасные»."""
    import time
    import ai_quota
    import config
    import gemini_solver
    import health
    await ai_quota.take(1)
    await ai_quota.take(1)
    await ai_quota.take(2)
    text = await health.report()
    assert "Вопросов сегодня: 3, у самого активного — 2 · дневного лимита нет" in text
    assert "упёрлась в лимит" not in text
    monkeypatch.setattr(config, "AI_DAILY_LIMIT", 40)
    monkeypatch.setattr(gemini_solver, "_primary_rest_until", time.monotonic() + 290)   # 4 мин 50 с → «ещё 5 мин»
    text = await health.report()
    assert "лимит 40 на человека" in text and "упёрлась в лимит — ещё 5 мин" in text



@pytest.mark.asyncio
async def test_report_no_spare_no_resting_line(db, monkeypatch):
    """Без запасных моделей основная не «отдыхает» — и в /status про это ни слова."""
    import time
    import gemini_solver
    import health
    monkeypatch.setattr(gemini_solver, "GEMINI_FALLBACK_MODELS", [gemini_solver.GEMINI_MODEL])
    monkeypatch.setattr(gemini_solver, "_primary_rest_until", time.monotonic() + 600)
    assert gemini_solver.rest_status()[0] == 0
    assert "упёрлась в лимит" not in await health.report()
