"""
Своя группа в боте (этап 1: любая группа института): /group и первый /start.

Кто был в боте до этапа 1 — уже в своей группе (миграция). Новый человек
после /start пишет название группы, бот ищет её в справочнике расписания
(groups.search) и даёт кнопки; выбор — groups.choose. Сменить — /group.
"""

from aiogram import F, Router
from aiogram.filters import Command
from aiogram.fsm.context import FSMContext
from aiogram.fsm.state import State, StatesGroup
from aiogram.types import CallbackQuery, InlineKeyboardButton, InlineKeyboardMarkup, Message

from utils import esc

router = Router(name="group_pick")

ASK = "Из какой ты группы? Напиши название, например <b>УИБО-03-24</b>."


class GroupPick(StatesGroup):
    query = State()


async def ask_group(message: Message, state: FSMContext, intro: str = ""):
    await state.set_state(GroupPick.query)
    await message.answer((intro + "\n\n" if intro else "") + ASK, parse_mode="HTML")


@router.message(Command("group"))
async def cmd_group(message: Message, state: FSMContext):
    import groups
    from database import upsert_user
    user = message.from_user
    await upsert_user(user.id, user.username or "", user.full_name or "")
    g = await groups.of_user(user.id)
    await ask_group(message, state, f"Сейчас ты в группе <b>{esc(g['name'])}</b>." if g else "")


@router.message(GroupPick.query, F.text)
async def group_query(message: Message, state: FSMContext):
    import groups
    found = await groups.search(message.text)
    if not found:
        await message.answer("Не нашёл такую группу. Напиши, как в расписании: <b>УИБО-03-24</b>. "
                             "Передумал — /cancel", parse_mode="HTML")
        return
    kb = InlineKeyboardMarkup(inline_keyboard=[[InlineKeyboardButton(text=g["name"], callback_data=f"grp:{g['id']}")]
                                               for g in found[:8]])
    await message.answer("Выбери свою:", reply_markup=kb)


@router.callback_query(F.data.startswith("grp:"))
async def group_chosen(callback: CallbackQuery, state: FSMContext):
    import groups
    gid = callback.data.split(":", 1)[1]
    g = await groups.choose(callback.from_user.id, int(gid)) if gid.isdigit() else None
    if not g:
        await callback.answer("Такой группы нет", show_alert=True)
        return
    await state.clear()
    await callback.answer()
    text = f"Готово: ты в группе <b>{esc(g['name'])}</b>. Сменить — /group"
    try:
        await callback.message.edit_text(text, parse_mode="HTML")
    except Exception:
        await callback.message.answer(text, parse_mode="HTML")
    if g["own"]:
        from handlers.start import ask_optional
        await ask_optional(callback.message, callback.from_user.id)
