"""Объявления старосты (/announce) и очистка семестра (/clearsem). Доска ДЗ —
handlers/homework.py, зам/рейтинг/Пульс/статистика — handlers/group_tools.py
(подключены ниже к этому же роутеру)."""


from aiogram import Router, F, Bot
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import Message

from database import get_all_subscribed_users
from config import STAROSTA_ID, is_starosta

router = Router()


# ── Рассылка объявлений ───────────────────────────────────────────────────────

class AnnounceState(StatesGroup):
    waiting = State()


class ClearSemState(StatesGroup):
    confirm = State()


@router.message(Command("announce"))
async def cmd_announce(message: Message, state: FSMContext):
    if STAROSTA_ID and not is_starosta(message.from_user.id):
        await message.answer("❌ Только для старосты.")
        return
    await state.set_state(AnnounceState.waiting)
    await message.answer(
        "📢 Напиши объявление — отправлю всей группе.\n"
        "Можно текст, фото или документ.\n\n"
        "/cancel — отмена"
    )


@router.message(Command("cancel"), AnnounceState.waiting)
async def cancel_announce(message: Message, state: FSMContext):
    await state.clear()
    await message.answer("Отменено.")


@router.message(AnnounceState.waiting)
async def send_announce(message: Message, state: FSMContext, bot: Bot):
    await state.clear()
    users = await get_all_subscribed_users()

    sent = 0
    failed = 0
    wait = await message.answer(f"⏳ Рассылаю {len(users)} пользователям...")

    for uid in users:
        if uid == message.from_user.id:
            continue
        try:
            if message.photo:
                await bot.send_photo(uid, message.photo[-1].file_id,
                                     caption=f"📢 {message.caption or ''}")
            elif message.document:
                await bot.send_document(uid, message.document.file_id,
                                        caption=f"📢 {message.caption or ''}")
            elif message.text:
                # html_text, а не text: сохраняет форматирование старосты
                # (жирный, ссылки) и экранирует "<", "&" — с сырым text любое
                # "<3" или "R&D" в объявлении валило рассылку ВСЕМ получателям.
                await bot.send_message(uid, f"📢 <b>Объявление от старосты:</b>\n\n{message.html_text}",
                                       parse_mode="HTML")
            else:
                # Голосовое, видео, стикер и т.п. — раньше уходило текстом "None".
                await bot.copy_message(uid, message.chat.id, message.message_id)
            sent += 1
        except Exception:
            failed += 1

    await wait.edit_text(
        f"✅ Рассылка завершена!\n\n"
        f"Отправлено: {sent}\n"
        f"Ошибок: {failed}"
    )


# ── Очистка семестра ─────────────────────────────────────────────────────────

@router.message(Command("clearsem"))
async def cmd_clearsem(message: Message, state: FSMContext):
    if STAROSTA_ID and not is_starosta(message.from_user.id):
        await message.answer("❌ Только для старосты.")
        return
    await state.set_state(ClearSemState.confirm)
    await message.answer(
        "⚠️ <b>Это сбросит данные прошлого семестра:</b>\n\n"
        "• Дедалйн-трекер 🗓\n"
        "• Доску ДЗ 📝\n"
        "• Файлы 📁\n"
        "• Голосования 🗳\n\n"
        "<b>Подписки, настройки напоминаний и историю решений это НЕ тронет.</b>\n\n"
        "Продолжить? Напиши <b>да</b> для подтверждения, или <b>нет</b> для отмены.",
        parse_mode="HTML"
    )


@router.message(ClearSemState.confirm, F.text)
async def clearsem_confirm(message: Message, state: FSMContext):
    answer = message.text.strip().lower()
    if answer in ("да", "yes", "y", "д"):
        from database import clear_semester_data
        await clear_semester_data()
        await state.clear()
        await message.answer("🧹 Готово! Доска чистого семестра.")
    else:
        await state.clear()
        await message.answer("Отменено — данные сохранены.")


# ── Доска ДЗ и прочие команды группы — отдельными модулями (v5.0.3) ────────
# Порядок как был в одном файле: объявления и очистка семестра, дальше доска
# ДЗ (handlers/homework.py), дальше зам, рейтинг, Пульс, статистика.
from handlers import group_tools, homework  # noqa: E402

for _sub in (homework, group_tools):
    router.include_router(_sub.router)
