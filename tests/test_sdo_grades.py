"""Баллы БРС из журнала СДО (sdo_grades) и проверка доступа к Пульсу."""
import httpx
import pytest

import sdo_grades


def _item(level, kind, name, grade, rng, href="", cls=""):
    a = f'<a class="gradeitemheader" href="{href}">{name}</a>' if href else f'<span class="gradeitemheader">{name}</span>'
    return (f'<tr><th class="level{level} item column-itemname"><div class="d-flex"><div>'
            f'<span class="d-block text-uppercase small dimmed_text">{kind}</span>{a}</div></div></th>'
            f'<td class="level{level} itemcenter column-grade {cls}">{grade}</td>'
            f'<td class="level{level} column-range">{rng}</td></tr>')


def _cat(level, name):
    return f'<tr><th class="level{level} category column-itemname" colspan="3"><div>{name}</div></th></tr>'


A = "https://online-edu.mirea.ru/mod/assign/view.php?id="
# Журнал «Основы предпринимательской деятельности» — как на скрине владельца 01.10
REPORT = ('<table class="generaltable user-grade"><thead><tr><th>Элемент оценивания</th></tr></thead><tbody>'
          + _cat(1, "Основы предпринимательской деятельности_Зачет (часть 1/1) [I.26-27]")
          + _item(2, "Вычисляемая оценка", "Текущий контроль", "-", "0–45")
          + _item(2, "Заполняемый вручную элемент", "Посещаемость", "5,0", "0–20")
          + _item(2, "Вычисляемая оценка", "Семестровый контроль", "-", "0–40")
          + _item(2, "Заполняемый вручную элемент", "Трудовая деятельность", "-", "0–5")
          + _item(2, "Заполняемый вручную элемент", "Достижения", "-", "0–10")
          + _item(2, "Вычисляемая оценка", "Сумма баллов", "5,0", "0–130")
          + _item(2, "Вычисляемая оценка", "Оценка за промежуточную аттестацию", "Не зачтено", "Не зачтено–Зачтено")
          + _cat(2, "Текущий контроль")
          + _item(3, "Задание", "Практическое задание 1", "6,00", "0–8", A + "101", "gradepass")
          + _item(3, "Задание", "Защита проекта", "-", "0–15", A + "102")
          + _item(3, "Задание", "Практическое задание 2", "2,00", "0–12", A + "103", "gradefail")
          + _item(3, "Тест", "Тест по курсу", "-", "0–10", "https://online-edu.mirea.ru/mod/quiz/view.php?id=104")
          + _item(2, "Заполняемый вручную элемент", "Балл за зачет(доп)", "-", "0–10")
          + _cat(2, "Самостоятельная работа")
          + _item(3, "Задание", "Самостоятельная работа (СР-1)", "", "–", A + "105")
          + '</tbody></table>')


def test_parse_report_like_owner_screenshot():
    s = sdo_grades.summarize(sdo_grades.parse_report(REPORT), "Основы предпринимательской деятельности_Зачет (часть 1/1) [I.26-27]")
    assert s["kind"] == "credit" and s["score"] == 5 and s["max"] == 130 and s["final"] == "Не зачтено"
    assert [(c["name"], c["max"]) for c in s["categories"]] == [
        ("Текущий контроль", 45), ("Посещаемость", 20), ("Семестровый контроль", 40),
        ("Трудовая деятельность", 5), ("Достижения", 10), ("Балл за зачет(доп)", 10)]
    tk = s["categories"][0]
    assert tk["tk"] and tk["score"] == 8          # «-» в журнале — сумма выставленных работ
    # работы — только текущего контроля, без самостоятельной
    assert [(w["name"], w["max"], w["passed"]) for w in s["works"]] == [
        ("Практическое задание 1", 8, True), ("Защита проекта", 15, None),
        ("Практическое задание 2", 12, False), ("Тест по курсу", 10, None)]
    assert s["works"][3]["module"] == "quiz" and s["works"][0]["cmid"] == 101
    assert (s["works_total"], s["works_passed"], s["works_graded"]) == (4, 1, 2)
    assert s["marks"] == [{"at": 40, "label": "зачёт"}] and not s["closed"] and s["need"] == 35


def test_exam_marks_and_closed():
    rep = sdo_grades.parse_report(REPORT.replace("Сумма баллов", "Сумма баллов").replace(">5,0</td>\n", ""))
    s = sdo_grades.summarize(rep, "Анализ данных_Экзамен (часть 1/1) [I.26-27]")
    assert s["kind"] == "exam" and [m["label"] for m in s["marks"]] == ["3", "4", "5"]
    rep["items"][5]["grade"] = 64.0      # «Сумма баллов»
    s = sdo_grades.summarize(rep, "Анализ данных_Экзамен")
    assert s["closed"] and s["need_label"] == "5" and s["need"] == 16


ASSIGN_OPEN = """<div>Открыто с: вторник, 1 сентября 2026, 00:00</div><table>
<tr><th>Проходной балл</th><td>3,0</td></tr><tr><th>Состояние ответа на задание</th><td>Ответы на задание еще не представлены</td></tr>
<tr><th>Оставшееся время</th><td>14 дн. 3 час.</td></tr><tr><th>Срок сдачи</th><td>четверг, 15 октября 2026, 23:59</td></tr></table>
<form><input type="hidden" name="action" value="editsubmission"><button>Добавить ответ на задание</button></form>"""
ASSIGN_OFFLINE = """<div>Открывается: четверг, 15 октября 2026, 16:29</div><table><tr><th>Проходной балл</th><td>6,0</td></tr>
<tr><th>Состояние ответа на задание</th><td>Ответ на задание должен быть представлен вне сайта</td></tr></table>"""
ASSIGN_SENT = """<table><tr><th>Состояние ответа на задание</th><td>Отправлено для оценивания</td></tr></table>"""


def test_assign_page_and_status():
    p = sdo_grades.parse_assign_page(ASSIGN_OPEN)
    assert p["pass"] == 3 and p["can_submit"] and not p["submitted"] and p["due"] == "четверг, 15 октября 2026, 23:59"
    w = {"grade": None, "passed": None}
    assert sdo_grades.work_status(w, p) == "todo"
    assert sdo_grades.work_status(w, sdo_grades.parse_assign_page(ASSIGN_SENT)) == "wait"
    off = sdo_grades.parse_assign_page(ASSIGN_OFFLINE)
    assert off["offline"] and off["opens"] and sdo_grades.work_status(w, off) == "offline"
    assert sdo_grades.work_status({"grade": 2, "passed": False}, None) == "low"


@pytest.mark.asyncio
async def test_webapp_grades(db, monkeypatch):
    from fastapi.testclient import TestClient
    import sdo_accounts
    import webapp.server as server
    from tests.test_webapp_home import BOT_TOKEN, _make_init_data
    monkeypatch.setattr(server.deps, "BOT_TOKEN", BOT_TOKEN)
    sdo_grades._cache.clear()

    async def courses(client):
        return [{"id": 18672, "name": "Основы предпринимательской деятельности_Зачет (часть 1/1) [I.26-27]",
                 "title": "Основы предпринимательской деятельности"}]

    def moodle(request):
        url = str(request.url)
        if "grade/report/user" in url:
            return httpx.Response(200, text=REPORT)
        if "id=103" in url:
            return httpx.Response(200, text=ASSIGN_OPEN)
        if "id=102" in url:
            return httpx.Response(200, text=ASSIGN_OFFLINE)
        return httpx.Response(200, text="<p></p>")

    real = httpx.AsyncClient
    monkeypatch.setattr(httpx, "AsyncClient", lambda *a, **kw: real(*a, transport=httpx.MockTransport(moodle), **kw))
    monkeypatch.setattr(sdo_grades, "this_semester_courses", courses)
    c, h = TestClient(server.app), {"X-Telegram-Init-Data": _make_init_data()}

    assert c.get("/api/sdo/grades", headers=h).status_code == 403            # СДО не подключён
    await db.save_sdo_session(222, sdo_accounts.encrypt("abcdef0123456789abcdef0123"))
    data = c.get("/api/sdo/grades", headers=h).json()
    (course,) = data["courses"]
    assert course["id"] == 18672 and course["score"] == 5 and course["works_total"] == 4

    d = c.get("/api/sdo/grades/18672", headers=h).json()
    by = {w["name"]: w for w in d["works"]}
    assert by["Практическое задание 2"]["status"] == "low" and by["Практическое задание 2"]["pass_mark"] == 3
    assert by["Защита проекта"]["status"] == "offline" and not by["Защита проекта"]["can_submit"]
    assert by["Практическое задание 1"]["status"] == "ok"
    assert c.post("/api/pulsecheck", headers=h).status_code == 403            # не староста


@pytest.mark.asyncio
async def test_pulse_check(monkeypatch):
    import pulse_check
    real = httpx.AsyncClient

    def use(handler):
        monkeypatch.setattr(httpx, "AsyncClient", lambda *a, **kw: real(*a, transport=httpx.MockTransport(handler), **kw))

    use(lambda r: httpx.Response(403, text="<title>DDoS-Guard</title> geoblocked: has restricted access"))
    res = await pulse_check.check()
    assert not res["ok"] and "DDoS-Guard" in res["why"] and pulse_check.text(res).startswith("🔴")
    use(lambda r: httpx.Response(200, text="<html>Пульс</html>"))
    assert (await pulse_check.check())["ok"]


@pytest.mark.asyncio
async def test_pulsecheck_command_only_for_starosta(monkeypatch):
    import time
    from aiogram import Bot, Dispatcher
    from aiogram.fsm.storage.memory import MemoryStorage
    from aiogram.types import Chat, Message, Update, User
    import pulse_check
    from handlers import announce
    from tests.conftest import STAROSTA_ID
    from tests.test_solver_render import RecordingSession

    async def fake():
        return {"ok": False, "status": 403, "why": "блокирует (DDoS-Guard не пускает адрес сервера)", "ms": 120}

    monkeypatch.setattr(pulse_check, "check", fake)
    bot = Bot(token="123456:TEST-TOKEN-NOT-REAL-AAAAAAAAAAAAAAAAAAA", session=RecordingSession())
    dp = Dispatcher(storage=MemoryStorage())
    dp.include_router(announce.router)
    try:
        for i, uid in enumerate((222, STAROSTA_ID)):
            u = User(id=uid, is_bot=False, first_name="X")
            msg = Message(message_id=i + 1, date=0, chat=Chat(id=uid, type="private"), from_user=u, text="/pulsecheck")
            await dp.feed_update(bot, Update(update_id=int(time.time()) + i, message=msg))
    finally:
        announce.router._parent_router = None
    assert [t for t, _ in bot.session.sent] == ["🔴 Пульс МИРЭА с сервера бота: блокирует (DDoS-Guard не пускает адрес сервера)\nHTTP 403 · 120 мс"]
