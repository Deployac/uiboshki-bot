"""Свой вход в СДО (sdo_accounts) и сдача файла в задание (sdo_submit)."""
import base64
import json
from urllib.parse import parse_qs

import httpx
import pytest

import sdo_accounts
import sdo_submit

COOKIE = "abcdef0123456789abcdef0123"
ASSIGN = "https://online-edu.mirea.ru/mod/assign/view.php?id=4242"

EDIT_PAGE = """<html><body>
<form autocomplete="off" action="https://online-edu.mirea.ru/mod/assign/view.php" method="post" id="mform1">
<input name="lastmodified" type="hidden" value="1700000000">
<input name="id" type="hidden" value="4242">
<input name="userid" type="hidden" value="77">
<input name="action" type="hidden" value="savesubmission">
<input name="sesskey" type="hidden" value="SK123">
<input name="_qf__mod_assign_submission_form" type="hidden" value="1">
<input name="files_filemanager" type="hidden" value="555">
<input type="submit" name="submitbutton" value="Сохранить">
<input type="submit" name="cancel" value="Отмена">
</form>
<script>M.form_filemanager.init(Y, {"maxbytes":10485760,"areamaxbytes":-1,"itemid":555,
"client_id":"6511ab3c9d1e2","context":{"id":9001,"contextlevel":70},
"repositories":{"3":{"id":"3","name":"Файлы","type":"recent"},
"5":{"id":"5","name":"Загрузить файл","type":"upload","icon":"x.svg"}}});</script>
</body></html>"""

VIEW_SUBMITTED = ('<table><tr><th>Состояние ответа</th>'
                  '<td class="submissionstatussubmitted cell c1">Отправлено для оценивания</td></tr></table>')
DRAFT_SAVED = '<div><form><input type="hidden" name="action" value="submit"><button>Отправить задание</button></form></div>'
CONFIRM_PAGE = """<form method="post" action="https://online-edu.mirea.ru/mod/assign/view.php">
<input type="hidden" name="id" value="4242"><input type="hidden" name="action" value="confirmsubmit">
<input type="hidden" name="sesskey" value="SK123">
<input type="checkbox" name="submissionstatement" value="1">
<input type="submit" name="submitbutton" value="Продолжить"></form>"""


class FakeMoodle:
    def __init__(self, edit=EDIT_PAGE, drafts=False, logged_in=True, exists=False):
        self.edit, self.drafts, self.logged_in, self.exists = edit, drafts, logged_in, exists
        self.calls = []

    def __call__(self, request: httpx.Request) -> httpx.Response:
        url = str(request.url)
        self.calls.append((request.method, url, request.content))
        if not self.logged_in:
            if "/login/index.php" in url:
                return httpx.Response(200, text="login")
            return httpx.Response(303, headers={"Location": "https://online-edu.mirea.ru/login/index.php"})
        if request.method == "GET" and url.endswith("/my/"):
            return httpx.Response(200, text="dashboard")
        if "action=editsubmission" in url:
            return httpx.Response(200, text=self.edit)
        if "repository_ajax.php?action=upload" in url:
            assert b'name="repo_upload_file"; filename="' in request.content
            assert b"%PDF-work" in request.content
            if self.exists:
                return httpx.Response(200, json={"event": "fileexists",
                    "existingfile": {"filename": "work.pdf", "filepath": "/"},
                    "newfile": {"filename": "work (1).pdf", "filepath": "/"}})
            return httpx.Response(200, json={"url": "x", "id": 555, "file": "work.pdf"})
        if "repository_ajax.php?action=overwrite" in url:
            return httpx.Response(200, json={"filepath": "/"})
        if "action=submit" in url:
            return httpx.Response(200, text=CONFIRM_PAGE)
        if request.method == "POST" and "mod/assign/view.php" in url:
            return httpx.Response(200, text=DRAFT_SAVED if self.drafts else VIEW_SUBMITTED)
        if request.method == "GET" and "mod/assign/view.php" in url:
            return httpx.Response(200, text=VIEW_SUBMITTED)
        return httpx.Response(404)

    def posts(self):
        return [(u, parse_qs(c.decode())) for m, u, c in self.calls
                if m == "POST" and "mod/assign/view.php" in u]


@pytest.fixture
def moodle(monkeypatch):
    fake = FakeMoodle()
    real = httpx.AsyncClient
    monkeypatch.setattr(httpx, "AsyncClient",
                        lambda *a, **kw: real(*a, transport=httpx.MockTransport(fake), **kw))
    return fake


def test_cookie_encrypted_and_cleaned():
    token = sdo_accounts.encrypt(COOKIE)
    assert COOKIE not in token and sdo_accounts.decrypt(token) == COOKIE
    assert sdo_accounts.decrypt("мусор") is None
    assert sdo_accounts.clean_cookie(f" MoodleSession={COOKIE}; ") == COOKIE
    assert sdo_accounts.clean_cookie("привет") is None


def test_cmid_and_can_submit():
    assert sdo_submit.cmid_of(ASSIGN) == 4242
    assert sdo_submit.cmid_of("https://online-edu.mirea.ru/mod/quiz/view.php?id=1") is None
    assert sdo_submit.can_submit({"description": ASSIGN, "external_id": "sdo:1"})
    assert not sdo_submit.can_submit({"description": ASSIGN, "external_id": None})   # личный


def test_parse_edit_page():
    page = sdo_submit.parse_edit_page(EDIT_PAGE)
    assert (page["repo_id"], page["ctx_id"], page["itemid"], page["client_id"]) == ("5", "9001", "555", "6511ab3c9d1e2")
    assert page["fields"]["action"] == "savesubmission" and "cancel" not in page["fields"]
    with pytest.raises(sdo_submit.SubmitError, match="Срок сдачи истёк"):
        sdo_submit.parse_edit_page('<div class="alert alert-danger">Срок сдачи истёк</div>')


@pytest.mark.asyncio
async def test_submit_file(moodle):
    res = await sdo_submit.submit_file(COOKIE, 4242, "work.pdf", b"%PDF-work")
    assert res["status"] == "Отправлено для оценивания"
    (url, form), = moodle.posts()
    assert form["files_filemanager"] == ["555"] and form["sesskey"] == ["SK123"]
    assert form["submitbutton"] == ["Сохранить"]


@pytest.mark.asyncio
async def test_submit_overwrites_and_confirms_draft(moodle):
    moodle.exists, moodle.drafts = True, True
    await sdo_submit.submit_file(COOKIE, 4242, "work.pdf", b"%PDF-work")
    assert any("action=overwrite" in u for _, u, _ in moodle.calls)
    confirm = moodle.posts()[-1][1]
    assert confirm["action"] == ["confirmsubmit"] and confirm["submissionstatement"] == ["1"]


@pytest.mark.asyncio
async def test_submit_too_big_for_assignment(moodle):
    with pytest.raises(sdo_submit.SubmitError, match="10 МБ"):
        await sdo_submit.submit_file(COOKIE, 4242, "big.pdf", b"%PDF-work" + b"0" * 11 * 1024 * 1024)


@pytest.mark.asyncio
async def test_webapp_connect_and_submit(db, moodle, monkeypatch):
    from fastapi.testclient import TestClient
    import webapp.server as server
    from tests.test_webapp_home import BOT_TOKEN, _make_init_data
    monkeypatch.setattr(server, "BOT_TOKEN", BOT_TOKEN)
    did = await db.add_deadline("Практическая работа №3", ASSIGN, "2026-10-05", None, 0, external_id="sdo:1")
    c, h = TestClient(server.app), {"X-Telegram-Init-Data": _make_init_data()}

    assert c.get("/api/sdo/status", headers=h).json()["state"] == "off"
    item = next(d for d in c.get("/api/deadlines", headers=h).json()["items"] if d["id"] == did)
    assert item["can_submit"]
    body = {"deadline_id": did, "name": "work.pdf", "data": base64.b64encode(b"%PDF-work").decode()}
    assert c.post("/api/sdo/submit", json=body, headers=h).status_code == 403     # не подключён

    assert c.post("/api/sdo/connect", json={"cookie": "x"}, headers=h).status_code == 400
    assert c.post("/api/sdo/connect", json={"cookie": "MoodleSession=" + COOKIE}, headers=h).json()["state"] == "ok"
    row = await db.get_sdo_session(222)
    assert COOKIE not in json.dumps(row)                                          # в базе только шифр

    res = c.post("/api/sdo/submit", json=body, headers=h)
    assert res.status_code == 200 and res.json()["status"] == "Отправлено для оценивания"

    moodle.logged_in = False                                                     # СДО разлогинил
    assert c.post("/api/sdo/submit", json=body, headers=h).status_code == 403
    assert c.get("/api/sdo/status", headers=h).json()["state"] == "expired"
    assert c.post("/api/sdo/disconnect", headers=h).json()["state"] == "off"


@pytest.mark.asyncio
async def test_keepalive_marks_expired_and_tells_once(db, moodle):
    await db.save_sdo_session(222, sdo_accounts.encrypt(COOKIE))
    sent = []

    class Bot:
        async def send_message(self, chat_id, text, **kw):
            sent.append(chat_id)

    await sdo_accounts.keepalive_all(Bot())
    assert (await db.get_sdo_session(222))["status"] == "ok" and not sent
    moodle.logged_in = False
    await sdo_accounts.keepalive_all(Bot())
    await sdo_accounts.keepalive_all(Bot())
    assert (await db.get_sdo_session(222))["status"] == "expired" and sent == [222]


NO_FORM = """<html><body><noscript><div class="alert alert-danger">JavaScript отключен в вашем браузере.</div></noscript>
<div role="main"><h2>Практическая работа №1</h2></div></body></html>"""
VIEW_CLOSED = """<noscript><div class="alert alert-danger">JavaScript отключен в вашем браузере.</div></noscript>
<table><tr><th>Состояние ответа</th><td>Ни одной попытки</td></tr>
<tr><th>Состояние оценивания</th><td>Не оценено</td></tr>
<tr><th>Оставшееся время</th><td>Задание просрочено на: 5 дн.</td></tr></table>"""


@pytest.mark.asyncio
async def test_no_form_explains_from_assignment_page(moodle, monkeypatch):
    # живой тест 01.10: формы не было, а бот показал плашку «JavaScript отключен» из <noscript>
    moodle.edit = NO_FORM
    real_call = moodle.__call__

    def call(request):
        url = str(request.url)
        if request.method == "GET" and url.endswith("view.php?id=4242"):
            return httpx.Response(200, text=VIEW_CLOSED)
        return real_call(request)

    monkeypatch.setattr(FakeMoodle, "__call__", lambda self, r: call(r))
    with pytest.raises(sdo_submit.SubmitError) as e:
        await sdo_submit.submit_file(COOKIE, 4242, "work.pdf", b"%PDF-work")
    msg = str(e.value)
    assert "JavaScript" not in msg
    assert "Ни одной попытки" in msg and "просрочено на: 5 дн." in msg
    assert not any(m == "POST" for m, _, _ in moodle.calls)                     # ничего не грузили
