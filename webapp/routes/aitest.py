"""Страницы выбора модели ИИ (ai_bench.py, /aitest у старосты): отбор
(k=report) и слепое голосование (k=vote) — по одной последней, по подписанной
ссылке — без initData, чтобы открывались в обычном браузере телефона.
Выбор в слепом тесте — на сервере (/aitest/pick с той же подписью), итог
текстом — &view=result: его читает Claude, без копирования с телефона."""

import hashlib
import hmac
import time

from fastapi import APIRouter, HTTPException
from fastapi.responses import HTMLResponse, PlainTextResponse
from pydantic import BaseModel

from webapp import deps

router = APIRouter()
DAYS = 7


def _sig(exp: int, kind: str) -> str:
    return hmac.new(deps.BOT_TOKEN.encode(), f"aitest:{kind}:{exp}".encode(), hashlib.sha256).hexdigest()[:32]


def link(kind: str = "vote") -> str:
    exp = int(time.time()) + DAYS * 86400
    return f"{(deps.WEBAPP_URL or '').rstrip('/')}/aitest?k={kind}&exp={exp}&sig={_sig(exp, kind)}"


HEADERS = {"Cache-Control": "no-store", "X-Robots-Tag": "noindex"}


def _check(k: str, exp: int, sig: str) -> None:
    import ai_bench
    if (not deps.BOT_TOKEN or k not in ai_bench.SETTINGS or exp < time.time()
            or not hmac.compare_digest(sig, _sig(exp, k))):
        raise HTTPException(404)


@router.get("/aitest")
async def aitest_page(k: str = "vote", exp: int = 0, sig: str = "", view: str = ""):
    import ai_bench
    _check(k, exp, sig)
    html = await ai_bench.load(k)
    if not html:
        raise HTTPException(404)
    if k == "vote" and view == "result":
        return PlainTextResponse(await ai_bench.vote_result(), headers=HEADERS)
    return HTMLResponse(html, headers=HEADERS)


class Pick(BaseModel):
    i: int
    j: int


@router.get("/aitest/pick")
async def aitest_picks(k: str = "", exp: int = 0, sig: str = ""):
    import ai_bench
    _check("vote", exp, sig)
    return {"picks": await ai_bench.vote_picks()}


@router.post("/aitest/pick")
async def aitest_pick(body: Pick, k: str = "", exp: int = 0, sig: str = ""):
    import ai_bench
    _check("vote", exp, sig)
    current = await ai_bench.vote_pick(body.i, body.j)
    if current is None:
        raise HTTPException(400)
    return {"picks": current}
