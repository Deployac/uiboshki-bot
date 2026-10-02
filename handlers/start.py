from aiogram import Router, F
from aiogram.filters import CommandStart, Command, CommandObject
from aiogram.types import Message, CallbackQuery, InlineKeyboardMarkup, InlineKeyboardButton

from database import upsert_user, set_subscription, get_user
from config import BOT_USERNAME, GROUP_NAME, SCHEDULE_HOUR, SCHEDULE_MINUTE
from keyboards import MAIN_KB, ACTIONS_KB, app_button, webapp_keyboard
from utils import esc, split_by_lines

router = Router()


async def send_file_to(bot, user_id: int, fid) -> bool:
    """Файл из «Файлов» в личку: WebApp сама отдать его не может (file_id
    живёт только у бота). False — файла нет."""
    from database import get_files
    target = next((f for f in await get_files() if str(f["id"]) == str(fid)), None)
    if not target:
        return False
    await bot.send_document(
        user_id, target["file_id"],
        caption=f"📄 <b>{esc(target['title'])}</b>" + (f" ({esc(target['subject'])})" if target.get('subject') else ""),
        parse_mode="HTML",
    )
    return True


async def send_hw_to(bot, user_id: int, hw_id) -> bool:
    """Файл ДЗ в личку (кнопка «Открыть файл» у ДЗ в WebApp)."""
    from group_context import list_homework
    item = next((h for h in await list_homework(500) if str(h["id"]) == str(hw_id)), None)
    if not item or not item.get("file_id"):
        return False
    caption = f"📝 <b>{esc(item['subject'])}</b>" + (f"\n{esc(item['content'][:900])}" if item.get("content") else "")
    if item.get("file_type") == "photo":
        await bot.send_photo(user_id, item["file_id"], caption=caption, parse_mode="HTML")
    else:
        await bot.send_document(user_id, item["file_id"], caption=caption, parse_mode="HTML")
    return True


@router.message(CommandStart(deep_link=True))
async def cmd_start_deeplink(message: Message, command: CommandObject):
    """Диплинк t.me/bot?start=file_<id> / hw_<id> — запасной путь кнопки
    «Открыть» в WebApp (основной — /api/files/{id}/send, без «/start» в
    чате). Само «/start file_…» стираем, чтобы чат не зарастал. Просто
    /start без параметра идёт в обычный cmd_start ниже."""
    user = message.from_user
    await upsert_user(user.id, user.username or "", user.full_name or "")
    payload = command.args or ""
    if payload.startswith(("file_", "hw_")):
        is_file = payload.startswith("file_")
        key = payload.split("_", 1)[1]
        ok = await (send_file_to if is_file else send_hw_to)(message.bot, user.id, key)
        if not ok:
            await message.answer("❌ Файл не найден (возможно, его удалили)." if is_file
                                 else "❌ Файл ДЗ не найден (возможно, его удалили).")
        try:
            await message.delete()
        except Exception:
            pass
        return
    await cmd_start(message)


@router.message(CommandStart())
async def cmd_start(message: Message):
    user = message.from_user
    await upsert_user(user.id, user.username or "", user.full_name or "")
    # Одно короткое сообщение с одной кнопкой. Сначала оно уходит с
    # ReplyKeyboardRemove (убрать старую большую клавиатуру у тех, у кого она
    # осталась), потом к нему же цепляется кнопка «Открыть приложение».
    sent = await message.answer(start_text(user.first_name), parse_mode="HTML", reply_markup=MAIN_KB)
    kb = app_button()
    if kb:
        try:
            await sent.edit_reply_markup(reply_markup=kb)
        except Exception:
            await message.answer("👇", reply_markup=kb)
    await ask_optional(message, user.id)


# ── Предметы по выбору (optional_subjects.py) ───────────────────────────────

def _optional_kb(i: int) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[[
        InlineKeyboardButton(text="🎖 Хожу", callback_data=f"opt:{i}:1"),
        InlineKeyboardButton(text="Не хожу", callback_data=f"opt:{i}:0"),
    ]])


async def ask_optional(message: Message, user_id: int, all_subjects: bool = False):
    """Спросить про предметы по выбору: после /start — только те, на которые
    ещё не ответил; /optional — все (чтобы поменять ответ)."""
    from config import OPTIONAL_SUBJECTS
    from database import get_optional_answers
    from optional_subjects import pending_for
    subjects = OPTIONAL_SUBJECTS if all_subjects else await pending_for(user_id)
    answers = await get_optional_answers(user_id) if all_subjects else {}
    for s in subjects:
        now = ("\nСейчас: " + ("хожу" if answers[s] else "не хожу")) if s in answers else ""
        await message.answer(
            f"🎖 <b>{esc(s)}</b> — ходишь?\nЕсли нет, уберу эти пары из твоего расписания и напоминаний.{now}",
            parse_mode="HTML", reply_markup=_optional_kb(OPTIONAL_SUBJECTS.index(s)))
    if all_subjects and not subjects:
        await message.answer("Предметов по выбору нет.")


@router.message(Command("optional"))
async def cmd_optional(message: Message):
    await ask_optional(message, message.from_user.id, all_subjects=True)


@router.callback_query(F.data.startswith("opt:"))
async def optional_answer(callback: CallbackQuery):
    from config import OPTIONAL_SUBJECTS
    from database import set_optional_answer
    _, i, attend = callback.data.split(":")
    if not i.isdigit() or int(i) >= len(OPTIONAL_SUBJECTS):
        await callback.answer("Устарело", show_alert=True)
        return
    subject = OPTIONAL_SUBJECTS[int(i)]
    await set_optional_answer(callback.from_user.id, subject, attend == "1")
    text = (f"🎖 <b>{esc(subject)}</b> — буду показывать эти пары." if attend == "1"
            else f"Ок, <b>{esc(subject)}</b> убрал из твоего расписания. Передумаешь — /optional")
    await callback.answer()
    try:
        await callback.message.edit_text(text, parse_mode="HTML")
    except Exception:
        pass


@router.message(Command("app"))
async def cmd_app(message: Message):
    kb = webapp_keyboard()
    if not kb:
        await message.answer("🚧 Приложение скоро появится — его ещё не включили.")
        return
    await message.answer(
        "🚀 Расписание, дедлайны, ДЗ, файлы и чат с ИИ — в одном окне.",
        reply_markup=kb,
    )


@router.message(F.text == "⋯ Действия")
async def cmd_actions(message: Message):
    await message.answer("Выбери действие:", reply_markup=ACTIONS_KB)


# Кнопка «Действия» не может сама «нажать» команду за пользователя — раньше
# бот просто присылал голое "/add". Теперь — понятная подсказка, в которой
# команда кликабельна: одно касание, и понятно, что будет дальше.
ACTION_HINTS = {
    "add_deadline":   "➕ Свой дедлайн — нажми /add\n(видишь только ты; общие добавляет староста)",
    "upload":         "📤 Загрузить лекции и методички пачкой — нажми /upload\n"
                      "Выберешь предмет и пересылай файлы — ИИ их прочитает.",
    "lookup":         "🔍 Чужое расписание по всему МИРЭА:\n"
                      "/teacher Фамилия — преподаватель\n/group УИБО-02-24 — группа\n/room А-18 — аудитория",
    "solve_lectures": "📖 Решить строго по лекциям предмета — нажми /solve_lectures\n"
                      "(обычная /solve тоже опирается на лекции, если они загружены)",
    "history":        "📜 Прошлые решения — /history",
    "feed":           "🗣 Анонимный пост в «Подслушано» — нажми /feed",
    "anon":           "❓ Анонимный вопрос старосте — нажми /anon",
    "add_hw":         "📝 Добавить ДЗ на доску (староста и зам) — /addhw",
    "solve_ds":       "🐋 Решить через DeepSeek — нажми /solve_ds",
}


@router.callback_query(F.data.startswith("act:"))
async def handle_action(callback: CallbackQuery):
    action = callback.data.split(":")[1]
    uid = callback.from_user.id
    await callback.answer()

    if action in ACTION_HINTS:
        await callback.bot.send_message(uid, ACTION_HINTS[action])

    elif action == "nextweek":
        from schedule_parser import get_next_week_schedule
        wait = await callback.bot.send_message(uid, "⏳ Загружаю следующую неделю...")
        text = await get_next_week_schedule()
        await callback.bot.delete_message(uid, wait.message_id)
        for chunk in split_by_lines(text):
            await callback.bot.send_message(uid, chunk, parse_mode="HTML")

    elif action == "vote":
        await callback.bot.send_message(
            uid,
            "🗳 <b>Голосование</b>\n\n"
            "Создать: /vote Твой вопрос\n"
            "Например: <code>/vote Идём на пары в пятницу?</code>\n\n"
            "Посмотреть текущее: /vote",
            parse_mode="HTML"
        )

    elif action == "settings":
        await upsert_user(uid, callback.from_user.username or "", callback.from_user.full_name or "")
        text, kb = _settings_view(await get_user(uid))
        await callback.bot.send_message(uid, text, parse_mode="HTML", reply_markup=kb)

    elif action == "subscribe":  # старая кнопка в уже отправленных сообщениях
        await upsert_user(uid, callback.from_user.username or "", callback.from_user.full_name or "")
        user = await get_user(uid)
        is_sub = user and user.get("subscribed")
        await set_subscription(uid, 0 if is_sub else 1)
        await callback.bot.send_message(uid, "🔕 Отписался от уведомлений." if is_sub else "✅ Подписан на уведомления!")


def start_text(first_name: str) -> str:
    return (
        f"👋 Привет, <b>{esc(first_name or 'друг')}</b>!\n\n"
        f"Я — бот группы <b>{GROUP_NAME}</b>. Всё главное — в приложении:\n"
        "расписание, дедлайны, баллы БРС, файлы и сдача работ в СДО.\n\n"
        "А сюда я сам пришлю:\n"
        "🔔 напоминание до пары\n"
        "☀️ расписание на день — утром\n"
        "⏰ дедлайны, которые горят\n\n"
        "И можно просто написать мне: «скинь лекцию 3 по анализу данных», "
        "задать вопрос или прислать фото задачи — отвечу."
    )


HELP_TEXT = (
    "📖 <b>Что умею</b>\n\n"
    "🚀 Всё главное — в приложении: кнопка «Открыть приложение» слева от поля ввода "
    "или /app.\n\n"
    "💬 <b>Просто напиши</b>\n"
    "«когда следующая пара», «что сдавать на неделе», «скинь практику 3 по …», "
    "вопрос по учёбе или фото задачи.\n\n"
    "⚡ <b>Быстро в чате</b>\n"
    "<i>Классика: команды работают как раньше, а всё новое появляется в приложении.</i>\n"
    "/schedule · /tomorrow · /week — расписание\n"
    "/next — следующая пара · /deadlines — дедлайны\n"
    f"/teacher Фамилия · /group {GROUP_NAME} · /room А-18 — чужое расписание\n"
    f"В любом чате набери <code>@{BOT_USERNAME}</code> — и отправь туда расписание\n\n"
    "⚙️ <b>Уведомления</b>\n"
    "В приложении: ☰ Ещё → Уведомления — дни, погода, корпус, напоминания.\n"
    "/settings — коротко в чате · /optional — предметы по выбору\n\n"
    "💬 <b>Группа</b>\n"
    "/anon — анонимный вопрос старосте · /feed — «Подслушано» · /vote — голосование"
)

STAROSTA_HELP = (
    "\n\n👑 <b>Для старосты</b>\n"
    "/announce — рассылка · /addhw — добавить ДЗ\n"
    "/setzam ID — назначить зама\n"
    "/syncfiles — загрузить файлы\n"
    "/importdeadlines · /syncsdo — дедлайны из СДО\n"
    "/sdofiles — файлы из СДО (сначала покажу, что нашлось)\n"
    "/tidyfiles — понятные названия файлов («Лекция 3. Тема»)\n"
    "/sdoclean — убрать дедлайны прошлого семестра\n"
    "/backup — копия базы (сама приходит каждую ночь) · /restore — восстановить из копии\n"
    "/stats — статистика бота · /status — состояние бота (СДО, бэкап, ошибки)\n"
    "/pulsecheck — пускает ли Пульс\n"
    "/delpost ID — удалить пост из ленты\n"
    "/clearsem — сбросить всё под новый семестр"
)


@router.message(Command("help"))
async def cmd_help(message: Message):
    # Команды старосты видит только староста (и зам): остальным они только
    # мешали — и всё равно отвечали бы «только для старосты».
    from database import is_editor
    text = HELP_TEXT
    if await is_editor(message.from_user.id):
        text += STAROSTA_HELP
    await message.answer(text, parse_mode="HTML", reply_markup=app_button())


@router.message(Command("subscribe"))
@router.message(F.text == "🔔 Подписка")
async def cmd_subscribe(message: Message):
    await upsert_user(message.from_user.id, message.from_user.username or "", message.from_user.full_name or "")
    await set_subscription(message.from_user.id, 1)
    await message.answer(f"✅ Подписан! Расписание каждое утро в {SCHEDULE_HOUR}:{SCHEDULE_MINUTE:02d} 🌅")


@router.message(Command("unsubscribe"))
async def cmd_unsubscribe(message: Message):
    await set_subscription(message.from_user.id, 0)
    await message.answer("🔕 Отписался. Вернуться — /subscribe")


@router.message(Command("setreminder"))
async def cmd_setreminder(message: Message):
    parts = message.text.split()
    if len(parts) < 2 or not parts[1].isdigit():
        await message.answer("Использование: /setreminder 15")
        return
    mins = int(parts[1])
    if mins < 1 or mins > 60:
        await message.answer("❌ Введи число от 1 до 60")
        return
    import notify_prefs
    await notify_prefs.set_all_reminders(message.from_user.id, mins)
    await message.answer(f"✅ Буду напоминать за <b>{mins} минут</b> до пары!\n"
                         "Отдельно для первой пары и после перемены — в приложении: ☰ Ещё → Уведомления.",
                         parse_mode="HTML")


REMINDER_CHOICES = (5, 10, 15, 30)


def _settings_view(user: dict | None) -> tuple[str, InlineKeyboardMarkup]:
    """Настройки — кнопками, а не «напиши /setreminder 15»: одно касание."""
    import notify_prefs
    mins = (user or {}).get("reminder_minutes", 15) or 15
    sub = bool((user or {}).get("subscribed"))
    prefs = notify_prefs.merge((user or {}).get("notify"))
    text = (
        "⚙️ <b>Настройки</b>\n\n"
        f"🔔 Утренняя рассылка и напоминания: <b>{'включены' if sub else 'выключены'}</b>\n"
        f"⏰ Перед парой: {notify_prefs.summary(prefs)}\n"
        "Кнопки ниже ставят одно время на все пары.\n\n"
        f"Рассылка приходит каждое утро в {SCHEDULE_HOUR}:{SCHEDULE_MINUTE:02d}: расписание и погода.\n\n"
        "Дни недели, погода, подсказка про другой корпус — в приложении: ☰ Ещё → Уведомления."
    )
    from keyboards import app_button
    app = app_button("🔔 Настроить в приложении", "notify")
    kb = InlineKeyboardMarkup(inline_keyboard=([app.inline_keyboard[0]] if app else []) + [
        [InlineKeyboardButton(text="🔕 Выключить уведомления" if sub else "🔔 Включить уведомления",
                              callback_data="set:sub")],
        [InlineKeyboardButton(text=("✓ " if m == mins else "") + f"за {m} мин", callback_data=f"set:rem:{m}")
         for m in REMINDER_CHOICES],
    ])
    return text, kb


@router.message(Command("settings"))
@router.message(F.text == "⚙️ Настройки")
async def cmd_settings(message: Message):
    await upsert_user(message.from_user.id, message.from_user.username or "", message.from_user.full_name or "")
    text, kb = _settings_view(await get_user(message.from_user.id))
    await message.answer(text, parse_mode="HTML", reply_markup=kb)


@router.callback_query(F.data.startswith("set:"))
async def settings_change(callback: CallbackQuery):
    uid = callback.from_user.id
    await upsert_user(uid, callback.from_user.username or "", callback.from_user.full_name or "")
    parts = callback.data.split(":")
    if parts[1] == "sub":
        user = await get_user(uid)
        await set_subscription(uid, 0 if (user and user.get("subscribed")) else 1)
    elif parts[1] == "rem" and len(parts) == 3 and parts[2].isdigit() and int(parts[2]) in REMINDER_CHOICES:
        import notify_prefs
        await notify_prefs.set_all_reminders(uid, int(parts[2]))
    text, kb = _settings_view(await get_user(uid))
    try:
        await callback.message.edit_text(text, parse_mode="HTML", reply_markup=kb)
    except Exception:
        pass  # «message is not modified» — нажали уже выбранное
    await callback.answer("Сохранено ✓")


@router.message(F.text == "🏆 Рейтинг")
async def rating_button(message: Message):
    from handlers.group_tools import cmd_rating
    await cmd_rating(message)


@router.message(F.text == "📝 ДЗ")
async def hw_button(message: Message):
    from handlers.homework import cmd_hw
    await cmd_hw(message)
