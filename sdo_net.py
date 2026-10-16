"""Клиент к СДО (online-edu.mirea.ru) с «предохранителем».

16.10: СДО перестал пускать сервер бота (соединение висит до таймаута), и
каждый запрос приложения к СДО ждал по 30 с — вкладка СДО крутила загрузку
без конца, приложение писало «Сервер не отвечает», хотя сервер отвечал.
Теперь: не соединились с СДО — следующие DOWN_SECONDS запросы к нему сразу
падают той же ошибкой httpx.ConnectError (её уже ловят и пишут «СДО сейчас
не отвечает»), потом снова пробуем. Соединение ждём не дольше CONNECT_TIMEOUT.
"""
import logging
import time

import httpx

logger = logging.getLogger(__name__)

DOWN_SECONDS = 180
CONNECT_TIMEOUT = 6

_down_until = 0.0


def is_down() -> bool:
    return time.monotonic() < _down_until


def mark_down() -> None:
    global _down_until
    _down_until = time.monotonic() + DOWN_SECONDS


def reset() -> None:
    global _down_until
    _down_until = 0.0


def client(cookie: str, timeout: float = 30) -> httpx.AsyncClient:
    c = httpx.AsyncClient(cookies={"MoodleSession": cookie}, follow_redirects=True,
                          timeout=httpx.Timeout(timeout, connect=min(timeout, CONNECT_TIMEOUT)))
    send = c.send

    async def guarded(request, **kw):
        if is_down():
            raise httpx.ConnectError("СДО недоступен с сервера (недавно не ответил)", request=request)
        try:
            return await send(request, **kw)
        except (httpx.ConnectError, httpx.ConnectTimeout) as e:
            logger.warning(f"СДО: нет соединения с сервера ({type(e).__name__}) — {DOWN_SECONDS} с не пробуем")
            mark_down()
            raise

    c.send = guarded
    return c
