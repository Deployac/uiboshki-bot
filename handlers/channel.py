"""Посты канала бота (/channel у старосты): список, точное превью в личку и
кнопка «В канал». Сами посты и отправка — channel_posts.py.
/channel redo — убрать из канала всё, что бот уже опубликовал, и выпустить
заново (например, когда поменялся вид постов). Закреп бот закрепляет сам."""

from aiogram import F, Router
from aiogram.filters import Command
from aiogram.types import CallbackQuery, InlineKeyboardButton, InlineKeyboardMarkup, Message

import config
from config import is_starosta
from utils import esc

router = Router()


def _kb(slug: str, done: bool) -> InlineKeyboardMarkup:
    first = (InlineKeyboardButton(text="✅ Уже в канале", callback_data="chan:noop") if done
             else InlineKeyboardButton(text="📣 В канал", callback_data=f"chan:pub:{slug}"))
    return InlineKeyboardMarkup(inline_keyboard=[[first,
                                                  InlineKeyboardButton(text="Следующий ▸", callback_data=f"chan:next:{slug}")]])


async def _list_text(posts, done) -> str:
    lines = [f"{'✅' if p['slug'] in done else '▫️'} <code>{i + 1}</code> {esc(p['title'])}" for i, p in enumerate(posts)]
    where = esc(config.CHANNEL_ID) if config.CHANNEL_ID else "⚠️ канал не задан — переменная CHANNEL_URL или CHANNEL_ID"
    return (f"📣 <b>Посты канала</b> · {where}\n\n" + "\n".join(lines) +
            "\n\nНиже — превью следующего поста ровно как в канале. <code>/channel N</code> — любой по номеру.")


async def _preview(bot, chat_id, posts, idx, done):
    from channel_posts import check, send_post
    post = posts[idx]
    problem = check(post)
    if problem:
        await bot.send_message(chat_id, f"⚠️ Пост {idx + 1} «{esc(post['title'])}»: {esc(problem)}", parse_mode="HTML")
        return
    await send_post(bot, chat_id, post, config.WEBAPP_URL)
    await bot.send_message(chat_id, f"👆 Превью · пост {idx + 1} из {len(posts)}", reply_markup=_kb(post["slug"], post["slug"] in done))


@router.message(Command("channel"))
async def cmd_channel(message: Message):
    if not is_starosta(message.from_user.id):
        await message.answer("❌ Только для старосты.")
        return
    from channel_posts import load_posts, published
    posts, done = load_posts(), await published()
    if (message.text or "").split()[1:2] == ["redo"]:
        n = len(done)
        if not n:
            await message.answer("В канале пока нет постов от бота — нечего перевыпускать.")
            return
        await message.answer(
            f"Убрать из канала {n} пост(ов), которые выпустил бот, и выпустить заново в новом виде?\n"
            "Комментарии к ним пропадут. Дальше — /channel, как в первый раз.",
            reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                InlineKeyboardButton(text="🗑 Убрать и перевыпустить", callback_data="chan:redo:yes")]]))
        return
    if not posts:
        await message.answer("Постов пока нет — они лежат в репозитории, channel/posts/.")
        return
    await message.answer(await _list_text(posts, done), parse_mode="HTML")
    arg = (message.text or "").split()[1:2]
    if arg and arg[0].isdigit() and 1 <= int(arg[0]) <= len(posts):
        idx = int(arg[0]) - 1
    else:
        idx = next((i for i, p in enumerate(posts) if p["slug"] not in done), None)
        if idx is None:
            await message.answer("Все посты уже в канале 🎉")
            return
    await _preview(message.bot, message.chat.id, posts, idx, done)


@router.callback_query(F.data.startswith("chan:"))
async def channel_button(callback: CallbackQuery):
    if not is_starosta(callback.from_user.id):
        await callback.answer("Только для старосты", show_alert=True)
        return
    from channel_posts import forget_published, load_posts, mark_published, post_link, published, send_post
    _, action, *rest = callback.data.split(":", 2)
    slug = rest[0] if rest else ""
    posts, done = load_posts(), await published()
    if action == "redo":
        ids = [i for v in done.values() for i in v.get("ids", [])]
        try:
            for k in range(0, len(ids), 100):
                await callback.bot.delete_messages(config.CHANNEL_ID, ids[k:k + 100])
        except Exception as e:
            await callback.answer("Не вышло удалить", show_alert=True)
            await callback.message.answer(f"⚠️ Не удалил: {esc(str(e))[:300]}\n"
                                          "Удали посты в канале руками, потом снова /channel redo.", parse_mode="HTML")
            return
        await forget_published()
        await callback.message.edit_reply_markup(reply_markup=None)
        await callback.message.answer(f"🗑 Убрал из канала {len(done)} пост(ов). Теперь /channel — выпускаем заново.")
        await callback.answer()
        return
    idx = next((i for i, p in enumerate(posts) if p["slug"] == slug), None)
    if action == "noop" or idx is None:
        await callback.answer("Уже в канале" if action == "noop" else "Такого поста больше нет")
        return
    if action == "next":
        await callback.answer()
        if idx + 1 >= len(posts):
            await callback.message.answer("Это был последний пост.")
            return
        await _preview(callback.bot, callback.message.chat.id, posts, idx + 1, done)
        return
    # action == "pub"
    if not config.CHANNEL_ID:
        await callback.answer("Канал не задан: переменная CHANNEL_URL или CHANNEL_ID", show_alert=True)
        return
    if slug in done:
        await callback.answer("Этот пост уже в канале", show_alert=True)
        return
    try:
        ids = await send_post(callback.bot, config.CHANNEL_ID, posts[idx], config.WEBAPP_URL)
    except Exception as e:
        await callback.answer("Не вышло — бот админ канала?", show_alert=True)
        await callback.message.answer(f"⚠️ Не опубликовал: {esc(str(e))[:300]}\n"
                                      "Проверь, что бот — админ канала с правом публиковать.", parse_mode="HTML")
        return
    await mark_published(slug, ids)
    if "pinned" in slug:              # закреп с оглавлением — сразу закрепить
        try:
            await callback.bot.pin_chat_message(config.CHANNEL_ID, ids[0], disable_notification=True)
        except Exception as e:
            await callback.message.answer(f"Не закрепил сам ({esc(str(e))[:200]}) — закрепи руками.", parse_mode="HTML")
    await callback.message.edit_reply_markup(reply_markup=_kb(slug, True))
    link = post_link(config.CHANNEL_ID, ids[0])
    await callback.message.answer(f"✅ В канале: «{esc(posts[idx]['title'])}»" + (f"\n{link}" if link else ""),
                                  parse_mode="HTML", reply_markup=InlineKeyboardMarkup(inline_keyboard=[[
                                      InlineKeyboardButton(text="Следующий ▸", callback_data=f"chan:next:{slug}")]]))
    await callback.answer("Опубликовано")
