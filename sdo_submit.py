"""
Сдача файла в задание СДО (Moodle, mod_assign) от имени студента — так же,
как это делает браузер:

1. GET view.php?id=<cmid>&action=editsubmission — форма ответа: sesskey,
   черновая область файлов (files_filemanager = draft itemid), настройки
   файлового менеджера (client_id, context, id репозитория «Загрузить файл»).
2. POST repository/repository_ajax.php?action=upload — файл в черновик.
   Если файл с таким именем уже есть — action=overwrite, как кнопка
   «Перезаписать» в браузере.
3. POST view.php — сохранить ответ (все поля формы как есть + submitbutton).
4. Если в задании нужно отдельно «Отправить на проверку» — action=submit
   и подтверждение (галочку «это моя работа» человек ставит в WebApp:
   экран «Файл уйдёт преподавателю от твоего имени»).

Ошибки — SubmitError с понятным текстом для WebApp.
"""

import re

import httpx
from bs4 import BeautifulSoup

from config import SDO_BASE_URL

MAX_BYTES = 20 * 1024 * 1024
CMID_RE = re.compile(r"/mod/assign/view\.php\?(?:[^#]*&)?id=(\d+)")


class SubmitError(Exception):
    pass


def cmid_of(url: str) -> int | None:
    m = CMID_RE.search(url or "")
    return int(m.group(1)) if m else None


def _notice(soup: BeautifulSoup) -> str:
    """Текст ошибки Moodle со страницы (почему не даёт сдать)."""
    for sel in (".alert-danger", ".alert-warning", ".errormessage", ".box.errorbox", ".alert"):
        el = soup.select_one(sel)
        if el and el.get_text(strip=True):
            return el.get_text(" ", strip=True)[:200]
    return ""


def form_fields(form) -> dict:
    """Поля формы так, как их отправил бы браузер (без кнопок)."""
    data = {}
    for el in form.find_all(["input", "textarea", "select"]):
        name = el.get("name")
        if not name or el.has_attr("disabled"):
            continue
        if el.name == "textarea":
            data[name] = el.get_text()
        elif el.name == "select":
            opt = el.find("option", selected=True) or el.find("option")
            data[name] = opt.get("value", opt.get_text()) if opt else ""
        else:
            kind = (el.get("type") or "text").lower()
            if kind in ("submit", "button", "image", "reset", "file"):
                continue
            if kind in ("checkbox", "radio") and not el.has_attr("checked"):
                continue
            data[name] = el.get("value", "")
    return data


def parse_edit_page(html: str) -> dict:
    """Форма ответа на странице editsubmission → всё, что нужно для загрузки."""
    soup = BeautifulSoup(html, "html.parser")
    area = soup.find("input", attrs={"name": "files_filemanager"})
    if not area:
        if soup.find(attrs={"name": re.compile(r"^onlinetext")}):
            raise SubmitError("в этом задании ответ пишется текстом на сайте, файл не прикрепить")
        raise SubmitError("СДО не даёт сдать: " + (_notice(soup) or "формы ответа нет — срок вышел или сдача закрыта"))
    form = area.find_parent("form")
    fields = form_fields(form)
    repo_id = None
    for block in re.findall(r"\{[^{}]*\"type\":\"upload\"[^{}]*\}", html):
        m = re.search(r"\"id\":\"?(\d+)", block)
        if m:
            repo_id = m.group(1)
            break
    ctx = re.search(r"\"context\":\{\"id\":\"?(\d+)", html) or re.search(r"\"contextid\":\"?(\d+)", html)
    client = re.search(r"\"client_id\":\"([0-9a-z]+)\"", html)
    maxbytes = re.search(r"\"maxbytes\":\"?(-?\d+)", html)
    if not (repo_id and ctx and fields.get("sesskey")):
        raise SubmitError("не разобрал форму сдачи в СДО — сдай на сайте")
    return {
        "action": form.get("action") or f"{SDO_BASE_URL}/mod/assign/view.php",
        "fields": fields,
        "itemid": area.get("value", ""),
        "sesskey": fields["sesskey"],
        "repo_id": repo_id,
        "ctx_id": ctx.group(1),
        "client_id": client.group(1) if client else "",
        "maxbytes": int(maxbytes.group(1)) if maxbytes else 0,
    }


def status_text(html: str) -> str:
    """Статус ответа на странице задания: «Отправлено для оценивания» и т.п."""
    soup = BeautifulSoup(html, "html.parser")
    el = soup.select_one("td.submissionstatussubmitted, td.submissionstatusdraft, "
                         "[class*=submissionstatussubmitted], [class*=submissionstatusdraft]")
    return el.get_text(" ", strip=True) if el else ""


async def _upload(client: httpx.AsyncClient, page: dict, name: str, data: bytes):
    base = {
        "sesskey": page["sesskey"], "repo_id": page["repo_id"], "itemid": page["itemid"],
        "ctx_id": page["ctx_id"], "client_id": page["client_id"], "env": "filemanager",
        "savepath": "/", "title": name, "author": "", "license": "unknown",
        "maxbytes": str(page["maxbytes"] or -1), "areamaxbytes": "-1",
    }
    resp = await client.post(f"{SDO_BASE_URL}/repository/repository_ajax.php?action=upload",
                             data=base, files={"repo_upload_file": (name, data)})
    try:
        res = resp.json()
    except ValueError:
        raise SubmitError("СДО не принял файл (ответ не JSON)")
    if isinstance(res, dict) and res.get("error"):
        raise SubmitError("СДО не принял файл: " + str(res["error"])[:200])
    if isinstance(res, dict) and res.get("event") == "fileexists":
        new, old = res.get("newfile") or {}, res.get("existingfile") or {}
        resp = await client.post(f"{SDO_BASE_URL}/repository/repository_ajax.php?action=overwrite", data={
            "sesskey": page["sesskey"], "client_id": page["client_id"], "itemid": page["itemid"],
            "existingfilename": old.get("filename", name), "existingfilepath": old.get("filepath", "/"),
            "newfilename": new.get("filename", ""), "newfilepath": new.get("filepath", "/"),
        })
        try:
            res = resp.json()
        except ValueError:
            res = {}
        if isinstance(res, dict) and res.get("error"):
            raise SubmitError("не вышло заменить старый файл: " + str(res["error"])[:200])


async def submit_file(cookie: str, cmid: int, name: str, data: bytes) -> dict:
    """Загрузить файл в задание cmid. → {"status": текст статуса в СДО, "url": ...}"""
    from sdo_parser import SdoSessionExpired, get_checked
    if not data:
        raise SubmitError("пустой файл")
    if len(data) > MAX_BYTES:
        raise SubmitError("файл больше 20 МБ")
    url = f"{SDO_BASE_URL}/mod/assign/view.php?id={cmid}"
    async with httpx.AsyncClient(cookies={"MoodleSession": cookie}, follow_redirects=True, timeout=60) as client:
        try:
            resp = await get_checked(client, url + "&action=editsubmission")
            page = parse_edit_page(resp.text)
            if page["maxbytes"] > 0 and len(data) > page["maxbytes"]:
                raise SubmitError(f"в этом задании файл не больше {page['maxbytes'] // (1024 * 1024) or 1} МБ")
            await _upload(client, page, name, data)
            form = dict(page["fields"], submitbutton="Сохранить")
            resp = await client.post(page["action"], data=form)
            if "/login/index.php" in str(resp.url):
                raise SdoSessionExpired("вход устарел")
            soup = BeautifulSoup(resp.text, "html.parser")
            if soup.find("input", attrs={"name": "files_filemanager"}):
                raise SubmitError("СДО не сохранил ответ: " + (_notice(soup) or "проверь задание на сайте"))
            # Черновики: ответ надо ещё «Отправить на проверку»
            if soup.find("input", attrs={"name": "action", "value": "submit"}) or "action=submit" in resp.text:
                resp = await get_checked(client, url + "&action=submit")
                confirm = BeautifulSoup(resp.text, "html.parser").find(
                    "input", attrs={"name": "action", "value": "confirmsubmit"})
                if confirm:
                    form = form_fields(confirm.find_parent("form"))
                    box = confirm.find_parent("form").find("input", attrs={"name": "submissionstatement"})
                    if box is not None:
                        form["submissionstatement"] = box.get("value") or "1"
                    form["submitbutton"] = "Продолжить"
                    resp = await client.post(f"{SDO_BASE_URL}/mod/assign/view.php", data=form)
            resp = await get_checked(client, url)
        except httpx.HTTPError:
            raise SubmitError("СДО не отвечает — попробуй позже")
    return {"status": status_text(resp.text), "url": url}


def can_submit(deadline: dict) -> bool:
    return cmid_of(deadline.get("description") or "") is not None and bool(deadline.get("external_id"))

