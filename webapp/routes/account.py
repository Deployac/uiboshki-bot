"""Свой профиль: /api/me, экран «Безопасность», уведомления, проверка Пульса
(староста) и персональный ICS-календарь."""

from fastapi import APIRouter, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

from config import is_starosta
from webapp.deps import CurrentUser

router = APIRouter()


@router.get("/api/me")
async def api_me(user: dict = CurrentUser):
    return {"id": user["id"], "first_name": user.get("first_name", ""), "username": user.get("username", "")}


@router.get("/api/security")
async def api_security(user: dict = CurrentUser):
    """Экран «Безопасность»: как защищены данные (без самих ключей)."""
    import ratelimit
    import sdo_accounts
    from webapp.auth import MAX_AUTH_AGE_SECONDS
    return {
        "sdo": (await sdo_accounts.status_for(user["id"]))["state"],
        "key_source": sdo_accounts.key_source(),
        "auth_max_hours": MAX_AUTH_AGE_SECONDS // 3600,
        "link_minutes": 10,
        "limits": {k: {"count": v[0], "minutes": max(1, v[1] // 60)} for k, v in ratelimit.LIMITS.items()},
        "events_days": 180,
    }


class NotifyBody(BaseModel):
    subscribed: bool | None = None
    reminder_minutes: int | None = None
    prefs: dict | None = None


async def _notify_view(uid: int) -> dict:
    import notify_prefs
    from config import DEADLINE_REMINDER_HOUR, DEADLINE_REMINDER_MINUTE, SCHEDULE_HOUR, SCHEDULE_MINUTE
    from database import get_user
    from schedule_parser import fetch_schedule_raw
    user = await get_user(uid) or {}
    try:
        home = notify_prefs.home_campus(await fetch_schedule_raw())
    except Exception:
        home = None
    return {"subscribed": bool(user.get("subscribed", 1)), "reminder_minutes": user.get("reminder_minutes") or 15,
            "reminder_choices": list(notify_prefs.REMINDER_CHOICES), "prefs": notify_prefs.merge(user.get("notify")),
            "remind": [{"key": k, **v} for k, v in notify_prefs.REMIND.items()],
            "home_campus": home, "morning_time": f"{SCHEDULE_HOUR}:{SCHEDULE_MINUTE:02d}",
            "deadline_time": f"{DEADLINE_REMINDER_HOUR}:{DEADLINE_REMINDER_MINUTE:02d}"}


@router.get("/api/notify")
async def api_notify(user: dict = CurrentUser):
    """Конструктор уведомлений (☰ Ещё → Уведомления), notify_prefs.py."""
    return await _notify_view(user["id"])


@router.post("/api/notify")
async def api_notify_save(body: NotifyBody, user: dict = CurrentUser):
    import notify_prefs
    from database import get_user, set_notify, set_reminder_minutes, set_subscription
    uid = user["id"]
    if body.subscribed is not None:
        await set_subscription(uid, 1 if body.subscribed else 0)
    if body.reminder_minutes is not None:
        if body.reminder_minutes not in notify_prefs.REMINDER_CHOICES:
            raise HTTPException(status_code=400, detail="такого времени напоминания нет")
        await set_reminder_minutes(uid, body.reminder_minutes)
    if body.prefs is not None:
        current = notify_prefs.merge((await get_user(uid) or {}).get("notify"))
        await set_notify(uid, notify_prefs.merge({**current, **body.prefs}))
    return await _notify_view(uid)


@router.post("/api/pulsecheck")
async def api_pulsecheck(user: dict = CurrentUser):
    """Пускает ли pulse.mirea.ru сервер бота — кнопка старосты в листе «СДО»."""
    if not is_starosta(user["id"]):
        raise HTTPException(status_code=403, detail="только для старосты")
    import pulse_check
    return await pulse_check.check()


# ── Персональный ICS-календарь (Фаза 12) ────────────────────────────────────
# /api/calendar/link — за initData (фронт WebApp узнаёт свою ссылку и может
# показать кнопку "скопировать"). /ics/{token} — БЕЗ initData: календарные
# приложения (Google/Apple/Outlook) сами периодически переопрашивают
# webcal-подписку и не умеют слать кастомные заголовки — секретность держится
# на непредсказуемости токена в самом пути (см. database.get_or_create_calendar_token).

@router.get("/api/calendar/link")
async def api_calendar_link(user: dict = CurrentUser):
    from database import get_or_create_calendar_token
    token = await get_or_create_calendar_token(user["id"])
    return {"token": token, "ics_path": f"/ics/{token}"}


@router.get("/ics/{token}")
async def ics_feed(token: str):
    from database import get_user_by_calendar_token
    from webapp.calendar_feed import build_ics_for_user
    owner = await get_user_by_calendar_token(token)
    if not owner:
        raise HTTPException(status_code=404, detail="ссылка недействительна")
    from optional_subjects import apply_for
    await apply_for(owner["user_id"])
    body = await build_ics_for_user(token)
    return Response(
        content=body,
        media_type="text/calendar; charset=utf-8",
        headers={"Content-Disposition": "inline; filename=schedule.ics"},
    )
