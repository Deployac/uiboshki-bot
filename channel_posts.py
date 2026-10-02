"""
Посты канала бота (этап 3): лежат в репозитории, публикует сам бот — админ
канала, — по кнопке старосты (`/channel`, handlers/channel.py).

Каждый пост — папка channel/posts/NN-имя/:
  • post.html — текст в разметке Telegram (HTML: <b>, <i>, <u>, <s>,
    <tg-spoiler>, <code>, <pre><code class="language-python">, <blockquote>,
    <blockquote expandable>, <a href>), до 4096 символов;
  • 1.png, 2.jpg… — картинки по порядку (одна — фото, несколько — альбом).

Почему через бота, а не руками в Telegram Web: разметка (раскрывающиеся
цитаты, блоки кода, альбомы) приходит ровно как задумано, а староста видит
точное превью у себя в личке до публикации.
"""

import json
import logging
import re
from pathlib import Path

logger = logging.getLogger(__name__)

POSTS_DIR = Path(__file__).parent / "channel" / "posts"
CAPTION_LIMIT = 1024     # подпись к фото/альбому
TEXT_LIMIT = 4096        # обычное сообщение
IMAGE_EXT = (".png", ".jpg", ".jpeg", ".webp")


def visible_len(html: str) -> int:
    """Длина текста так, как её считает Telegram — без тегов и с раскрытыми &amp;."""
    text = re.sub(r"<[^>]+>", "", html)
    return len(text.replace("&lt;", "<").replace("&gt;", ">").replace("&quot;", '"').replace("&amp;", "&"))


def title_of(html: str, slug: str) -> str:
    m = re.search(r"<b>(.*?)</b>", html, re.S)
    return re.sub(r"<[^>]+>", "", m.group(1)).strip() if m else slug


def load_posts(root: Path | None = None) -> list[dict]:
    """Все посты по порядку папок: [{"slug", "title", "html", "images"}]."""
    root = root or POSTS_DIR
    posts = []
    if not root.exists():
        return posts
    for d in sorted(p for p in root.iterdir() if p.is_dir()):
        f = d / "post.html"
        if not f.exists():
            continue
        html = f.read_text(encoding="utf-8").strip()
        images = sorted((p for p in d.iterdir() if p.suffix.lower() in IMAGE_EXT),
                        key=lambda p: (len(p.stem), p.stem))
        posts.append({"slug": d.name, "title": title_of(html, d.name), "html": html, "images": images})
    return posts


def check(post: dict) -> str:
    """Что не так с постом («» — всё в порядке): длина, число картинок."""
    n = visible_len(post["html"])
    if n > TEXT_LIMIT:
        return f"текст {n} символов — больше {TEXT_LIMIT}"
    if len(post["images"]) > 10:
        return "в альбоме больше 10 картинок"
    return ""


async def send_post(bot, chat_id, post: dict) -> list[int]:
    """Отправить пост (в канал или старосте — превью). Короткий текст —
    подписью к фото или альбому; длинный — альбом, а текст отдельным
    сообщением следом. → id отправленных сообщений."""
    from aiogram.types import FSInputFile, InputMediaPhoto, LinkPreviewOptions
    html, images = post["html"], post["images"]
    no_preview = LinkPreviewOptions(is_disabled=True)
    fits = visible_len(html) <= CAPTION_LIMIT
    ids = []
    if not images:
        m = await bot.send_message(chat_id, html, parse_mode="HTML", link_preview_options=no_preview)
        return [m.message_id]
    if len(images) == 1:
        m = await bot.send_photo(chat_id, FSInputFile(images[0]), caption=html if fits else None,
                                 parse_mode="HTML" if fits else None)
        ids.append(m.message_id)
    else:
        media = [InputMediaPhoto(media=FSInputFile(p)) for p in images]
        if fits:
            media[0] = InputMediaPhoto(media=FSInputFile(images[0]), caption=html, parse_mode="HTML")
        ids += [m.message_id for m in await bot.send_media_group(chat_id, media)]
    if not fits:
        m = await bot.send_message(chat_id, html, parse_mode="HTML", link_preview_options=no_preview)
        ids.append(m.message_id)
    return ids


async def published() -> dict:
    """{slug: {"ids": [...], "at": "…"}} — что уже в канале."""
    from database import get_setting
    raw = await get_setting("channel:published")
    try:
        return json.loads(raw) if raw else {}
    except ValueError:
        return {}


async def mark_published(slug: str, ids: list[int]):
    from datetime import datetime
    from zoneinfo import ZoneInfo
    from config import TIMEZONE
    from database import set_setting
    done = await published()
    done[slug] = {"ids": ids, "at": datetime.now(ZoneInfo(TIMEZONE)).isoformat(timespec="minutes")}
    await set_setting("channel:published", json.dumps(done, ensure_ascii=False))


def post_link(channel: str, msg_id: int) -> str:
    """t.me/<канал>/<id> для публичного канала (@имя), иначе пусто."""
    return f"https://t.me/{channel.lstrip('@')}/{msg_id}" if channel.startswith("@") else ""
