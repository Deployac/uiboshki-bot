"""
Inline-режим: в любом чате пишешь «@UiboshkiBot» — и отправляешь туда
карточку расписания: сегодня, завтра, неделя группы. Дальше в запросе можно
набрать фамилию преподавателя, группу или аудиторию — придёт их расписание
(справочник schedule_index). Включается один раз в BotFather: /setinline.

Если задан WEBAPP_URL — карточки картинками (schedule_card.py, тёмные, в
стиле приложения): Telegram сам забирает их по подписанной ссылке /card/…
с сервера бота. Без WEBAPP_URL — текстом, как раньше.

Карточки собираются только когда их спрашивают; расписание чужих — не больше
трёх и с ограничением по времени, чтобы Telegram успел получить ответ.
"""

import asyncio
import hashlib
import logging

from aiogram import Router
from aiogram.types import (
    InlineKeyboardButton, InlineKeyboardMarkup, InlineQuery, InlineQueryResultArticle, InlineQueryResultPhoto,
    InputTextMessageContent,
)

logger = logging.getLogger(__name__)
router = Router()

MAX_TEXT = 4000          # лимит текста сообщения Telegram — 4096
TARGET_TIMEOUT = 6.0
DAY_WORDS = {"сегодня": "today", "завтра": "tomorrow", "неделя": "week", "неделю": "week"}


def _cut(text: str) -> str:
    """Обрезать по строкам до лимита Telegram."""
    if len(text) <= MAX_TEXT:
        return text
    out = text[:MAX_TEXT].rsplit("\n", 1)[0]
    return out + "\n…"


def _app_kb() -> InlineKeyboardMarkup:
    from config import BOT_USERNAME
    return InlineKeyboardMarkup(inline_keyboard=[[
        InlineKeyboardButton(text="📱 Открыть в приложении", url=f"https://t.me/{BOT_USERNAME}?startapp")]])


def _article(rid: str, title: str, description: str, text: str) -> InlineQueryResultArticle:
    return InlineQueryResultArticle(
        id=hashlib.md5(rid.encode()).hexdigest(), title=title, description=description[:120],
        input_message_content=InputTextMessageContent(message_text=_cut(text), parse_mode="HTML",
                                                      disable_web_page_preview=True),
        reply_markup=_app_kb(),
    )


def _photo(rid: str, url: str, title: str, description: str, caption: str) -> InlineQueryResultPhoto:
    # превью — своим адресом (?thumb=1): с одной ссылкой на двоих фото в чате
    # приходило обрезанным снизу
    return InlineQueryResultPhoto(
        id=hashlib.md5(rid.encode()).hexdigest(), photo_url=url, thumbnail_url=url + "&thumb=1",
        title=title, description=description[:120], caption=caption, reply_markup=_app_kb(),
    )


def _card_base() -> str:
    from config import WEBAPP_URL
    return WEBAPP_URL.rstrip("/")


async def _own_results(only: str | None) -> list:
    from config import GROUP_NAME
    if base := _card_base():
        import schedule_card
        out = []
        for key, title, desc in (("today", f"📅 Сегодня — {GROUP_NAME}", "пары на сегодня"),
                                 ("tomorrow", f"🌙 Завтра — {GROUP_NAME}", "пары на завтра"),
                                 ("week", f"🗓 Неделя — {GROUP_NAME}", "вся неделя")):
            if only and key != only:
                continue
            url = schedule_card.card_url(base, key)
            out.append(_photo(f"own:{key}:{url}", url, title, desc, title))
        return out
    from schedule_parser import get_today_schedule, get_tomorrow_schedule, get_week_schedule
    cards = [("today", f"📅 Сегодня — {GROUP_NAME}", "пары на сегодня", get_today_schedule),
             ("tomorrow", f"🌙 Завтра — {GROUP_NAME}", "пары на завтра", get_tomorrow_schedule),
             ("week", f"🗓 Неделя — {GROUP_NAME}", "вся неделя", get_week_schedule)]
    out = []
    for key, title, desc, fn in cards:
        if only and key != only:
            continue
        text = await fn()
        out.append(_article(f"own:{key}:{hash(text)}", title, desc, text))
    return out


async def _target_results(query: str) -> list:
    import schedule_index
    from handlers.schedule import _TARGET_EMOJI, render_target_schedule
    found = (await schedule_index.search(query, limit=3))[:3]
    if base := _card_base():
        import schedule_card
        out = []
        for t in found:
            url = schedule_card.card_url(base, "target", t["type"], t["id"])
            title = f"{_TARGET_EMOJI[t['type']]} {t['title']}"
            out.append(_photo(f"t:{url}", url, title, "расписание на неделю", title))
        return out

    async def one(t):
        try:
            text = await asyncio.wait_for(render_target_schedule(t["id"], t["type"], t["title"]), TARGET_TIMEOUT)
        except Exception as e:
            logger.info(f"inline: {t['title']}: {type(e).__name__}")
            return None
        return _article(f"t:{t['type']}:{t['id']}:{hash(text)}", f"{_TARGET_EMOJI[t['type']]} {t['title']}",
                        "расписание на 2 недели", text)

    return [r for r in await asyncio.gather(*(one(t) for t in found)) if r]


@router.inline_query()
async def inline_schedule(query: InlineQuery):
    q = (query.query or "").strip()
    only = DAY_WORDS.get(q.lower())
    try:
        if not q or only:
            results = await _own_results(only)
        elif len(q) >= 3:
            results = await _target_results(q)
        else:
            results = []
    except Exception as e:
        logger.warning(f"inline: {e}")
        results = []
    await query.answer(results, cache_time=60, is_personal=True)
