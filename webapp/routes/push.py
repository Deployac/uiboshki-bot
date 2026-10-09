"""Веб-пуши PWA (этап 2 (г)): ключ VAPID и подписка устройства."""

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel

from webapp.deps import CurrentUser

router = APIRouter()


@router.get("/api/push/key")
async def push_key(user: dict = CurrentUser):
    import webpush
    return {"key": webpush.public_key_b64()}


class PushKeys(BaseModel):
    p256dh: str
    auth: str


class PushSub(BaseModel):
    endpoint: str
    keys: PushKeys


@router.post("/api/push/subscribe")
async def push_subscribe(body: PushSub, request: Request, user: dict = CurrentUser):
    from database.push import save_push_sub
    from webapp.routes.auth import _device
    if not push_host_ok(body.endpoint) or len(body.endpoint) > 1000:
        raise HTTPException(400, "не похоже на подписку браузера")
    await save_push_sub(user["id"], body.endpoint, body.keys.p256dh[:200], body.keys.auth[:100], _device(request))
    return {"ok": True}


# Куда браузеры принимают пуши (Chrome/Edge/Яндекс — FCM, Firefox — Mozilla,
# Safari — Apple). Любой другой https-адрес — отказ: сервер не шлёт POST куда
# попало (ревью безопасности 09.10).
PUSH_HOSTS = ("fcm.googleapis.com", "push.services.mozilla.com", "notify.windows.com", "push.apple.com")


def push_host_ok(endpoint: str) -> bool:
    from urllib.parse import urlsplit
    u = urlsplit(endpoint)
    host = (u.hostname or "").lower()
    return u.scheme == "https" and any(host == h or host.endswith("." + h) for h in PUSH_HOSTS)


class PushOff(BaseModel):
    endpoint: str


@router.post("/api/push/unsubscribe")
async def push_unsubscribe(body: PushOff, user: dict = CurrentUser):
    from database.push import delete_push_sub
    return {"ok": True, "removed": await delete_push_sub(body.endpoint, user["id"])}
