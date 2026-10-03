"""Сайт-презентация бота: /about.

Страница — webapp/static/site/index.html (свои стили и скрипт, без
Telegram). На ней два живых места:
  • настоящее приложение в рамке телефона — /about/demo: тот же index.html,
    что в Telegram, но вместо SDK Telegram подключён site/demo.js — заглушка
    Telegram, подменённое время и ответы API из записанных тестовых данных
    (site/demo.json, ничьих настоящих данных там нет);
  • поиск расписания любой группы, преподавателя или аудитории МИРЭА —
    по-настоящему, без входа: /about/api/search и /about/api/target (те же
    обработчики, что в приложении; ограничение частоты — по IP).
"""

import hashlib
import zlib

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse, Response

router = APIRouter()

def _site_dir():
    from webapp.server import STATIC_DIR
    return STATIC_DIR / "site"


def _client_key(request: Request) -> int:
    """Ключ для ratelimit: IP посетителя (за прокси Railway — первый из
    X-Forwarded-For). Отрицательный — не пересечётся с id пользователей."""
    ip = (request.headers.get("x-forwarded-for") or "").split(",")[0].strip()
    ip = ip or (request.client.host if request.client else "?")
    return -(zlib.crc32(ip.encode()) + 1)


@router.get("/about", include_in_schema=False)
@router.get("/about/", include_in_schema=False)
async def about_page():
    return FileResponse(_site_dir() / "index.html", media_type="text/html",
                        headers={"Cache-Control": "no-cache"})


@router.get("/about/demo", include_in_schema=False)
async def about_demo():
    """Приложение как в Telegram, но на демо-данных: base href — чтобы
    относительные js/… и app.css грузились от корня, а SDK Telegram
    заменён на site/demo.js (он же подменяет fetch для /api/…)."""
    from webapp.server import index_page
    page = await index_page()
    html = page.body.decode("utf-8")
    demo = _site_dir() / "demo.js"
    v = hashlib.sha1(demo.read_bytes() + (_site_dir() / "demo.json").read_bytes()).hexdigest()[:10]
    html = html.replace("<head>", '<head>\n<base href="/">', 1)
    html = html.replace('<script src="https://telegram.org/js/telegram-web-app.js"></script>',
                        f'<script src="site/demo.js?v={v}"></script>', 1)
    return Response(html, media_type="text/html", headers={"Cache-Control": "no-cache"})


@router.get("/about/api/search", include_in_schema=False)
async def about_search(request: Request, q: str = "", type: int = 0):
    import ratelimit
    from webapp.routes.schedule import api_search
    if not ratelimit.allow("site_search", _client_key(request)):
        raise HTTPException(status_code=429, detail="слишком часто — подожди минуту")
    return await api_search(q=q[:60], type=type, user={"id": 0})


@router.get("/about/api/target/{target_type}/{target_id}", include_in_schema=False)
async def about_target(request: Request, target_type: int, target_id: int):
    import ratelimit
    from webapp.routes.schedule import api_target
    if not ratelimit.allow("site_target", _client_key(request)):
        raise HTTPException(status_code=429, detail="слишком часто — подожди минуту")
    data = await api_target(target_type, target_id, user={"id": 0})
    data.pop("pinned", None)
    data["weeks"] = data["weeks"][:2]          # сайту хватит этой и следующей недели
    return data
