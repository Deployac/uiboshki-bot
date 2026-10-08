"""Страница слепого теста моделей ИИ (ai_bench.py, /aitest у старосты):
одна последняя, по подписанной ссылке — без initData, чтобы открывалась в
обычном браузере телефона."""

import hashlib
import hmac
import time

from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse

from webapp import deps

router = APIRouter()
DAYS = 7


def _sig(exp: int) -> str:
    return hmac.new(deps.BOT_TOKEN.encode(), f"aitest:{exp}".encode(), hashlib.sha256).hexdigest()[:32]


def link() -> str:
    exp = int(time.time()) + DAYS * 86400
    return f"{(deps.WEBAPP_URL or '').rstrip('/')}/aitest?exp={exp}&sig={_sig(exp)}"


@router.get("/aitest")
async def aitest_page(exp: int = 0, sig: str = ""):
    if not deps.BOT_TOKEN or exp < time.time() or not hmac.compare_digest(sig, _sig(exp)):
        raise HTTPException(404)
    import ai_bench
    html = await ai_bench.load()
    if not html:
        raise HTTPException(404)
    return HTMLResponse(html, headers={"Cache-Control": "no-store", "X-Robots-Tag": "noindex"})
