"""Вход в приложение без Telegram (этап 2, PLAN.md «Своё приложение»):
PWA и будущее нативное приложение. Telegram в России открывается через
«КВН», поэтому приложение не держится за initData:

  1. POST /api/auth/start — одноразовый код и ссылка t.me/<бот>?start=login_<код>;
  2. в боте: «Войти в приложение на … ?» → «Да, это я» (handlers/start.py);
  3. POST /api/auth/poll {code} — пока «wait»; подтвердил — токен сессии
     устройства (90 дней, продлевается при заходах), код сгорает.

Дальше запросы — с «Authorization: Bearer <токен>» (webapp/deps.py).
«Ещё → Устройства»: список входов, выйти на одном или везде.
"""

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from webapp.deps import CurrentUser

router = APIRouter()


def _device(request: Request) -> str:
    """«Chrome · Android» из User-Agent — чтобы в боте было видно, что за вход."""
    ua = request.headers.get("user-agent", "")
    browser = next((b for b in ("Edg", "YaBrowser", "Chrome", "Firefox", "Safari") if b in ua), "Браузер")
    browser = {"Edg": "Edge", "YaBrowser": "Яндекс Браузер"}.get(browser, browser)
    os_name = next((o for o, k in (("iPhone", "iPhone"), ("iPad", "iPad"), ("Android", "Android"),
                                   ("Windows", "Windows"), ("macOS", "Mac OS"), ("Linux", "Linux")) if k in ua), "")
    return f"{browser} · {os_name}" if os_name else browser


def _client_ip(request: Request) -> str:
    from webapp.routes.site import _client_key
    return _client_key(request)


@router.post("/api/auth/start")
async def auth_start(request: Request):
    import ratelimit
    from config import BOT_USERNAME
    from database.sessions import create_login
    if not ratelimit.allow("auth_start", _client_ip(request)):
        raise HTTPException(429, "Слишком много попыток — подожди минуту")
    code = await create_login(_device(request))
    return {"code": code, "link": f"https://t.me/{BOT_USERNAME}?start=login_{code}", "expires_in": 600}


class PollBody(BaseModel):
    code: str


@router.post("/api/auth/poll")
async def auth_poll(body: PollBody, request: Request):
    from database.sessions import get_login, redeem_login
    login = await get_login(body.code[:64])
    if not login:
        return {"status": "expired"}
    if login["status"] == "no":
        return {"status": "denied"}
    if login["status"] != "ok":
        return {"status": "wait"}
    got = await redeem_login(body.code)
    if not got:
        return {"status": "expired"}
    token, uid = got
    return {"status": "ok", "token": token, "user_id": uid}


@router.get("/api/auth/sessions")
async def auth_sessions(request: Request, user: dict = CurrentUser):
    from database.sessions import list_sessions, token_hash
    current = request.headers.get("authorization", "")[7:].strip()
    items = await list_sessions(user["id"])
    if current:
        from database._conn import connect
        async with connect() as db:
            row = await (await db.execute("SELECT id FROM sessions WHERE token_hash = ?",
                                          (token_hash(current),))).fetchone()
        for it in items:
            it["current"] = bool(row and it["id"] == row[0])
    return {"items": items}


@router.delete("/api/auth/sessions/{session_id}")
async def auth_revoke(session_id: int, user: dict = CurrentUser):
    from database.sessions import revoke_session
    if not await revoke_session(user["id"], session_id=session_id):
        raise HTTPException(404, "Нет такого входа")
    return {"ok": True}


@router.post("/api/auth/logout")
async def auth_logout(request: Request, everywhere: bool = False, user: dict = CurrentUser):
    from database.sessions import revoke_session
    token = request.headers.get("authorization", "")[7:].strip()
    n = await revoke_session(user["id"]) if everywhere else await revoke_session(user["id"], token=token or "-")
    return {"ok": True, "revoked": n}
