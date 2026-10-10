"""Страницы выбора модели ИИ (ai_bench.py, /aitest у старосты): отбор
(k=report) и слепое голосование (k=vote) — по одной последней, по подписанной
ссылке — без initData, чтобы открывались в обычном браузере телефона."""

import hashlib
import hmac
import time

from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse

from webapp import deps

router = APIRouter()
DAYS = 7


def _sig(exp: int, kind: str) -> str:
    return hmac.new(deps.BOT_TOKEN.encode(), f"aitest:{kind}:{exp}".encode(), hashlib.sha256).hexdigest()[:32]


def link(kind: str = "vote") -> str:
    exp = int(time.time()) + DAYS * 86400
    return f"{(deps.WEBAPP_URL or '').rstrip('/')}/aitest?k={kind}&exp={exp}&sig={_sig(exp, kind)}"


@router.get("/aitest")
async def aitest_page(k: str = "vote", exp: int = 0, sig: str = ""):
    import ai_bench
    if (not deps.BOT_TOKEN or k not in ai_bench.SETTINGS or exp < time.time()
            or not hmac.compare_digest(sig, _sig(exp, k))):
        raise HTTPException(404)
    html = await ai_bench.load(k)
    if not html:
        raise HTTPException(404)
    return HTMLResponse(html, headers={"Cache-Control": "no-store", "X-Robots-Tag": "noindex"})
