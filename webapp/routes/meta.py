"""/api/meta — что за сервер и какие версии приложения он ещё принимает
(этап 2: API как контракт). Своё приложение спрашивает это при запуске:
его версия ниже min_client — экран «Обнови приложение» (в магазинах версии
обновляются не мгновенно, как сайт). Без входа."""

import os
import re
from functools import lru_cache
from pathlib import Path

from fastapi import APIRouter

router = APIRouter()

API_VERSION = 1


@lru_cache(maxsize=1)
def server_version() -> str:
    """Последняя версия из CHANGELOG.md (v5.31.0) — та, что задеплоена."""
    try:
        text = (Path(__file__).resolve().parents[2] / "CHANGELOG.md").read_text(encoding="utf-8")
    except OSError:
        return ""
    found = re.findall(r"^### v(\d+\.\d+\.\d+)", text, re.M)
    return max(found, key=lambda v: tuple(int(x) for x in v.split(".")), default="")


def _min(platform: str) -> str:
    return os.getenv(f"APP_MIN_{platform.upper()}", "0.0.0")


@router.get("/api/meta")
async def api_meta():
    import oauth
    return {
        "api": API_VERSION,
        "server": server_version(),
        "min_client": {p: _min(p) for p in ("web", "android", "ios")},
        "login": ["telegram", *oauth.available()],   # VK/Яндекс — когда есть ключи
        "features": {"groups": True, "sessions": True, "offline": True},
        # ссылки для меню «Ещё» и экрана «Вход в СДО» своего приложения (как APP_CONFIG у WebApp)
        "links": await _links(),
    }


async def _links() -> dict:
    import config
    from webapp.server import _guide_link
    return {"bot": f"https://t.me/{config.BOT_USERNAME}", "channel": config.CHANNEL_URL or "",
            "contact": config.CONTACT_URL or "", "sdo_guide": await _guide_link()}
