"""
Слой доставки (этап 2 (г), PLAN.md «Своё приложение»): одна функция на все
рассылки — утро, напоминание перед парой, дедлайны, новые задания, обзор
недели. Сейчас доставляет в Telegram и веб-пушем на устройства, где человек
включил уведомления в PWA (webpush.py); потом сюда же — пуши своего
приложения (FCM, APNs, RuStore), без правки каждой рассылки.
"""

import logging
import re

logger = logging.getLogger(__name__)

TITLES = {"morning": "Доброе утро", "lesson": "Скоро пара", "deadlines": "Дедлайны",
          "new_tasks": "Новое в СДО", "weekly": "Неделя", "grades": "Новые баллы"}


def plain(html: str, limit: int = 180) -> str:
    """Текст пуша: без HTML-разметки, первые строки."""
    text = re.sub(r"<[^>]+>", "", html or "")
    text = re.sub(r"&lt;", "<", re.sub(r"&gt;", ">", re.sub(r"&amp;", "&", text)))
    text = re.sub(r"\n{2,}", "\n", text).strip()
    return text if len(text) <= limit else text[:limit - 1].rstrip() + "…"


async def push(user_id: int, kind: str, html: str, tab: str | None = None) -> int:
    """Веб-пуш на все устройства человека. → сколько ушло."""
    import webpush
    from database.push import delete_push_sub, get_push_subs
    subs = await get_push_subs(user_id)
    if not subs:
        return 0
    data = {"title": TITLES.get(kind, "УИБО-бот"), "body": plain(html),
            "url": "/app" + (f"?tab={tab}" if tab else ""), "tag": kind}
    sent = 0
    for sub in subs:
        try:
            code = await webpush.send(sub, data)
        except Exception as e:
            logger.info(f"пуш {user_id}: {type(e).__name__}: {e}")
            continue
        if code in (404, 410):
            await delete_push_sub(sub["endpoint"])      # подписку удалили в браузере
        elif code < 300:
            sent += 1
        else:
            logger.info(f"пуш {user_id}: сервис ответил {code}")
    return sent


async def deliver(bot, user_id: int, html: str, *, kind: str, tab: str | None = None, reply_markup=None,
                  parse_mode: str = "HTML"):
    """Сообщение человеку: Telegram (как раньше) + пуш на его устройства.
    Ошибка Telegram пробрасывается (рассылки её логируют), пуш — молча."""
    try:
        await push(user_id, kind, html, tab)
    except Exception as e:
        logger.info(f"доставка {user_id}: пуш не ушёл: {e}")
    from database.identities import is_local
    if is_local(user_id):
        return None               # вошёл через VK/Яндекс, Telegram нет — только пуш
    return await bot.send_message(user_id, html, parse_mode=parse_mode, reply_markup=reply_markup)
