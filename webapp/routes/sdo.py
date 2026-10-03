"""СДО: свой вход студента, сдача работ, баллы БРС, экран задания и
подписанные ссылки /sdl на файлы из СДО."""

import logging
import re

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import Response
from pydantic import BaseModel

from config import is_starosta
from webapp import deps
from webapp.deps import CurrentUser

logger = logging.getLogger(__name__)

router = APIRouter()


# ── СДО: свой вход и сдача работ (sdo_accounts.py, sdo_submit.py) ───────────

class SdoConnect(BaseModel):
    cookie: str


class SdoFile(BaseModel):
    name: str
    data: str  # base64


class SdoSubmit(BaseModel):
    deadline_id: int = 0
    cmid: int = 0
    name: str = ""
    data: str = ""  # base64 — один файл (старый формат)
    files: list[SdoFile] = []


@router.get("/api/sdo/status")
async def api_sdo_status(user: dict = CurrentUser):
    from sdo_accounts import status_for
    return dict(await status_for(user["id"]), starosta=is_starosta(user["id"]))


@router.post("/api/sdo/connect")
async def api_sdo_connect(body: SdoConnect, user: dict = CurrentUser):
    import sdo_accounts
    from database import save_sdo_session
    import ratelimit
    if not ratelimit.allow("sdo_connect", user["id"]):
        raise HTTPException(status_code=429, detail="слишком много попыток — попробуй через 10 минут")
    cookie = sdo_accounts.clean_cookie(body.cookie)
    if not cookie:
        raise HTTPException(status_code=400, detail="не похоже на MoodleSession — скопируй значение целиком")
    try:
        alive = await sdo_accounts.check(cookie)
    except Exception:
        raise HTTPException(status_code=502, detail="СДО сейчас не отвечает — попробуй позже")
    if not alive:
        raise HTTPException(status_code=400, detail="СДО не пускает с этой кукой — войди на сайте заново и скопируй новую")
    await save_sdo_session(user["id"], sdo_accounts.encrypt(cookie), sdo_accounts.first_check_at())
    import sdo_grades
    sdo_grades.forget(user["id"])
    return await sdo_accounts.status_for(user["id"])


@router.post("/api/sdo/disconnect")
async def api_sdo_disconnect(user: dict = CurrentUser):
    from database import delete_sdo_session
    from sdo_accounts import status_for
    await delete_sdo_session(user["id"])
    import sdo_grades
    sdo_grades.forget(user["id"])
    return await status_for(user["id"])


@router.get("/api/sdo/submit-rules")
async def api_sdo_submit_rules(cmid: int = 0, deadline_id: int = 0, user: dict = CurrentUser):
    """Что принимает задание — показать в листе «Сдать» до выбора файлов:
    типы («только .zip»), сколько файлов и какой размер."""
    import sdo_accounts
    import sdo_submit
    from database import get_deadline, set_sdo_status
    from sdo_parser import SdoSessionExpired
    if not cmid:
        d = await get_deadline(deadline_id)
        if not d or not sdo_submit.can_submit(d):
            raise HTTPException(status_code=404, detail="это не задание из СДО")
        cmid = sdo_submit.cmid_of(d["description"])
    cookie = await sdo_accounts.cookie_for(user["id"])
    if not cookie:
        raise HTTPException(status_code=403, detail="сначала подключи СДО: вкладка СДО → Вход")
    try:
        return await sdo_submit.submission_rules(cookie, cmid)
    except SdoSessionExpired:
        await set_sdo_status(user["id"], "expired")
        raise HTTPException(status_code=403, detail="вход в СДО устарел — подключи заново: вкладка СДО → Вход")
    except sdo_submit.SubmitError as e:
        raise HTTPException(status_code=502, detail=str(e))


@router.post("/api/sdo/submit")
async def api_sdo_submit(body: SdoSubmit, user: dict = CurrentUser):
    import base64
    import sdo_accounts
    import sdo_submit
    from database import get_deadline, set_sdo_status
    from sdo_parser import SdoSessionExpired
    import ratelimit
    if not ratelimit.allow("submit", user["id"]):
        raise HTTPException(status_code=429, detail="слишком много сдач подряд — попробуй через 10 минут")
    if body.cmid:
        cmid = body.cmid     # из «Текущего контроля»: задание своего курса, сдаёт своим входом
    else:
        d = await get_deadline(body.deadline_id)
        if not d or not sdo_submit.can_submit(d):
            raise HTTPException(status_code=404, detail="это не задание из СДО")
        cmid = sdo_submit.cmid_of(d["description"])
    cookie = await sdo_accounts.cookie_for(user["id"])
    if not cookie:
        raise HTTPException(status_code=403, detail="сначала подключи СДО: вкладка СДО → Вход")
    items = body.files or [SdoFile(name=body.name, data=body.data)]
    files = []
    try:
        for it in items:
            clean = re.sub(r'[\\/:*?"<>|]+', "_", it.name).strip() or "работа"
            files.append((clean[:120], base64.b64decode(it.data, validate=False)))
    except Exception:
        raise HTTPException(status_code=400, detail="файл повреждён")
    try:
        result = await sdo_submit.submit_file(cookie, cmid, files=files)
    except SdoSessionExpired:
        await set_sdo_status(user["id"], "expired")
        raise HTTPException(status_code=403, detail="вход в СДО устарел — подключи заново: вкладка СДО → Вход")
    except sdo_submit.SubmitError as e:
        raise HTTPException(status_code=400, detail=str(e))
    logger.info(f"СДО: {user['id']} сдал файл в задание {cmid}")
    import sdo_grades
    sdo_grades.forget(user["id"])    # статусы и баллы — заново
    return result


# ── Баллы БРС из СДО (sdo_grades.py) ─────────────────────────────────────────

async def _sdo_cookie(user_id: int) -> str:
    from sdo_accounts import cookie_for
    cookie = await cookie_for(user_id)
    if not cookie:
        raise HTTPException(status_code=403, detail="подключи СДО, чтобы видеть свои баллы")
    return cookie


@router.get("/api/sdo/grades")
async def api_sdo_grades(fresh: bool = False, user: dict = CurrentUser):
    import sdo_grades
    from database import set_sdo_status
    from sdo_parser import SdoSessionExpired
    cookie = await _sdo_cookie(user["id"])
    try:
        data = await sdo_grades.overview(user["id"], cookie, fresh=fresh)
    except SdoSessionExpired:
        await set_sdo_status(user["id"], "expired")
        raise HTTPException(status_code=403, detail="вход в СДО устарел — подключи заново: вкладка СДО → Вход")
    except Exception as e:
        logger.warning(f"Баллы СДО: {type(e).__name__}: {e}")
        raise HTTPException(status_code=502, detail="СДО сейчас не отвечает — попробуй позже")
    try:
        import sdo_history          # точка истории баллов на сегодня (график на экране предмета)
        await sdo_history.record(user["id"], data.get("courses") or [])
    except Exception as e:
        logger.info(f"история баллов: {e}")
    import sdo_goal                 # свои цели по предметам («4» вместо ближайшей «3»)
    return {**data, "goals": await sdo_goal.get_goals(user["id"])}


@router.get("/api/sdo/grades/{course_id}")
async def api_sdo_course(course_id: int, user: dict = CurrentUser):
    import sdo_grades
    from database import set_sdo_status
    from sdo_parser import SdoSessionExpired
    cookie = await _sdo_cookie(user["id"])
    try:
        data = await sdo_grades.course_detail(user["id"], cookie, course_id)
    except LookupError:
        raise HTTPException(status_code=404, detail="курс не найден")
    except SdoSessionExpired:
        await set_sdo_status(user["id"], "expired")
        raise HTTPException(status_code=403, detail="вход в СДО устарел — подключи заново: вкладка СДО → Вход")
    except Exception as e:
        logger.warning(f"Баллы СДО, курс {course_id}: {type(e).__name__}: {e}")
        raise HTTPException(status_code=502, detail="СДО сейчас не отвечает — попробуй позже")
    try:
        import sdo_history
        data = {**data, "history": await sdo_history.series(user["id"], course_id, data.get("score"))}
    except Exception as e:
        logger.info(f"история баллов: {e}")
    try:
        import attendance           # посещения лекций из баллов за посещаемость
        data = {**data, "attendance": await attendance.for_course(user["id"], data)}
    except Exception as e:
        logger.info(f"посещения: {type(e).__name__}: {e}")
    return {**data, "goal": await _goal(user["id"], data)}


async def _goal(user_id: int, course: dict) -> dict:
    """Цель по предмету: сколько не хватает, откуда взять, правило 75 % (sdo_goal.py)."""
    import sdo_goal
    goals = await sdo_goal.get_goals(user_id)
    return sdo_goal.plan(course, course.get("attendance"), goals.get(str(course["id"])))


class Goal(BaseModel):
    label: str | None = None     # «зачёт», «3», «4», «5»; None — снять свою цель


@router.post("/api/sdo/goal/{course_id}")
async def api_sdo_goal(course_id: int, body: Goal, user: dict = CurrentUser):
    """Своя цель по предмету — только для подсчёта в боте, на СДО не влияет."""
    import attendance
    import sdo_goal
    import sdo_grades
    from sdo_parser import SdoSessionExpired
    cookie = await _sdo_cookie(user["id"])
    try:
        course = await sdo_grades.course_detail(user["id"], cookie, course_id)
    except LookupError:
        raise HTTPException(status_code=404, detail="курс не найден")
    except SdoSessionExpired:
        raise HTTPException(status_code=403, detail="вход в СДО устарел — подключи заново: вкладка СДО → Вход")
    except Exception:
        raise HTTPException(status_code=502, detail="СДО сейчас не отвечает — попробуй позже")
    if body.label is not None and body.label not in [m["label"] for m in course.get("marks") or []]:
        raise HTTPException(status_code=400, detail="такой оценки у предмета нет")
    await sdo_goal.set_goal(user["id"], course_id, body.label)
    try:
        att = await attendance.for_course(user["id"], course)
    except Exception:
        att = None
    return await _goal(user["id"], {**course, "attendance": att})


class AttendanceMark(BaseModel):
    day: str
    mark: str | None = None      # "ok" — был, "excused" — уважительная, None — снять


@router.post("/api/sdo/attendance/{course_id}")
async def api_attendance_mark(course_id: int, body: AttendanceMark, user: dict = CurrentUser):
    """Своя отметка для лекции до начала истории посещаемости: какие именно
    лекции засчитаны, по баллам не видно — человек отмечает сам, но не больше,
    чем показывают баллы. Только для показа в боте, на СДО не влияет."""
    import attendance
    import sdo_grades
    from database import get_attendance_marks, set_attendance_mark
    from sdo_parser import SdoSessionExpired
    cookie = await _sdo_cookie(user["id"])
    try:
        course = await sdo_grades.course_detail(user["id"], cookie, course_id)
    except LookupError:
        raise HTTPException(status_code=404, detail="курс не найден")
    except SdoSessionExpired:
        raise HTTPException(status_code=403, detail="вход в СДО устарел — подключи заново: вкладка СДО → Вход")
    except Exception:
        raise HTTPException(status_code=502, detail="СДО сейчас не отвечает — попробуй позже")
    blank = await attendance.for_course(user["id"], course, manual={})
    marks = await get_attendance_marks(user["id"], course_id)
    why = attendance.check_mark(blank, marks, body.day, body.mark)
    if why:
        raise HTTPException(status_code=400, detail=why)
    await set_attendance_mark(user["id"], course_id, body.day, body.mark)
    return await attendance.for_course(user["id"], course)


# ── Задание СДО: описание, файлы преподавателя, сдача ────────────────────────
# Файлы из СДО лежат за входом студента (pluginfile.php), а Telegram скачивает
# по обычной ссылке — даём подписанную на 10 минут: /sdl/<токен>/<имя>.

def _sdl_token(user_id: int, path: str, exp: int) -> str:
    import base64
    import hashlib
    import hmac
    payload = base64.urlsafe_b64encode(f"{user_id}|{exp}|{path}".encode()).decode().rstrip("=")
    sig = hmac.new(deps.BOT_TOKEN.encode(), f"sdl:{payload}".encode(), hashlib.sha256).hexdigest()[:32]
    return f"{payload}.{sig}"


def _sdl_parse(token: str) -> tuple[int, str] | None:
    import base64
    import hashlib
    import hmac
    import time
    payload, _, sig = token.partition(".")
    good = hmac.new(deps.BOT_TOKEN.encode(), f"sdl:{payload}".encode(), hashlib.sha256).hexdigest()[:32]
    if not sig or not hmac.compare_digest(sig, good):
        return None
    try:
        uid, exp, path = base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)).decode().split("|", 2)
    except Exception:
        return None
    if int(exp) < time.time() or not path.startswith("/pluginfile.php/"):
        return None
    return int(uid), path


@router.get("/api/sdo/task/{cmid}")
async def api_sdo_task(cmid: int, request: Request, user: dict = CurrentUser):
    import time
    from urllib.parse import quote, urlparse
    import sdo_grades
    from database import set_sdo_status
    from sdo_parser import SdoSessionExpired
    cookie = await _sdo_cookie(user["id"])
    try:
        task = await sdo_grades.task_detail(cookie, cmid)
    except SdoSessionExpired:
        await set_sdo_status(user["id"], "expired")
        raise HTTPException(status_code=403, detail="вход в СДО устарел — подключи заново: вкладка СДО → Вход")
    except Exception as e:
        logger.warning(f"Задание СДО {cmid}: {type(e).__name__}: {e}")
        raise HTTPException(status_code=502, detail="СДО сейчас не отвечает — попробуй позже")
    base = (deps.WEBAPP_URL or str(request.base_url)).rstrip("/")
    exp = int(time.time()) + 600
    for f in task["files"] + task["mine"]:
        path = urlparse(f.pop("url")).path
        f["dl"] = f"{base}/sdl/{_sdl_token(user['id'], path, exp)}/{quote(f['name'], safe='')}"
    return task


@router.get("/sdl/{token}/{name}")
async def sdo_download(token: str, name: str):
    """Файл из СДО входом того, кому выдана ссылка (через Telegram.WebApp.downloadFile)."""
    import mimetypes
    from urllib.parse import quote
    from sdo_accounts import client_for, cookie_for
    from sdo_parser import SdoSessionExpired, get_checked
    from config import SDO_BASE_URL
    parsed = _sdl_parse(token)
    if not parsed:
        raise HTTPException(403, "Ссылка устарела — нажми «📥» ещё раз")
    uid, path = parsed
    cookie = await cookie_for(uid)
    if not cookie:
        raise HTTPException(403, "Вход в СДО не подключён")
    try:
        async with client_for(cookie, timeout=60) as client:
            resp = await get_checked(client, SDO_BASE_URL + path + "?forcedownload=1")
    except SdoSessionExpired:
        raise HTTPException(403, "Вход в СДО устарел")
    if resp.status_code != 200 or len(resp.content) > 50 * 1024 * 1024:
        raise HTTPException(404, "Файл не скачался из СДО")
    return Response(resp.content, media_type=resp.headers.get("content-type") or mimetypes.guess_type(name)[0] or "application/octet-stream",
                    headers={"Content-Disposition": f"attachment; filename*=UTF-8''{quote(name, safe='')}"})
