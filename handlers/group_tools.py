"""Группа: зам старосты (/setzam), рейтинг активности (/rating), здоровье
бота (/status), проверка Пульса (/pulsecheck) и статистика (/stats) — у старосты."""

from aiogram import Router, F
from aiogram.filters import Command
from aiogram.types import Message, InlineKeyboardMarkup, InlineKeyboardButton, CallbackQuery

from config import STAROSTA_ID, is_starosta
from database import init_hw_table, set_setting
from utils import esc, plural

router = Router()


@router.message(Command("setzam"))
async def cmd_setzam(message: Message):
    if STAROSTA_ID and not is_starosta(message.from_user.id):
        await message.answer("❌ Только для старосты.")
        return
    parts = message.text.split()
    if len(parts) < 2 or not parts[1].isdigit():
        await message.answer(
            "Использование: /setzam ID (числовой Telegram ID, не @username)\n"
            "Например: /setzam 123456789"
        )
        return
    await init_hw_table()
    await set_setting("zam_id", parts[1])
    await message.answer(f"✅ Зам установлен: {parts[1]}")


# ── Рейтинг активности ────────────────────────────────────────────────────────

@router.message(Command("rating"))
async def cmd_rating(message: Message):
    from database import get_solver_rating
    rows = await get_solver_rating(10)

    if not rows:
        await message.answer("📊 Рейтинг пока пустой — никто ещё не решал задачи через бота.")
        return

    medals = ["🥇", "🥈", "🥉"] + ["4️⃣", "5️⃣", "6️⃣", "7️⃣", "8️⃣", "9️⃣", "🔟"]
    lines = ["🏆 <b>Рейтинг активности</b>\n(по количеству решённых задач)\n"]

    for i, r in enumerate(rows):
        # f"@{username}" всегда truthy (даже "@None"/"@"), поэтому "Аноним"
        # раньше не показывался никогда — вместо него было "@None".
        name = r["full_name"] or (f"@{r['username']}" if r["username"] else "Аноним")
        lines.append(f"{medals[i]} {esc(name)} — {r['cnt']} {plural(r['cnt'], 'задача', 'задачи', 'задач')}")

    await message.answer("\n".join(lines), parse_mode="HTML")


@router.message(Command("status"))
async def cmd_status(message: Message):
    """Здоровье бота (health.py): СДО, расписание, бэкап, ошибки — только староста."""
    if STAROSTA_ID and not is_starosta(message.from_user.id):
        return
    import health
    await message.answer(await health.report(), parse_mode="HTML")


@router.message(Command("aitest"))
async def cmd_aitest(message: Message):
    """Слепое сравнение моделей ИИ на вопросах и лекциях группы (ai_bench.py) —
    только староста; ответы приходят ссылкой на страницу голосования."""
    if STAROSTA_ID and not is_starosta(message.from_user.id):
        return
    from config import OPENROUTER_API_KEY
    if not OPENROUTER_API_KEY:
        await message.answer("Нужен ключ OpenRouter: openrouter.ai → Keys, пополнить на $5 и "
                             "задать OPENROUTER_API_KEY в переменных Railway.")
        return
    import ai_bench
    from webapp.routes.aitest import link
    await message.answer("🧪 Гоняю модели на вопросах и лекциях группы — пара минут…")
    try:
        html, summary = await ai_bench.run(OPENROUTER_API_KEY)
    except Exception as e:
        await message.answer(f"Не вышло: {e}")
        return
    await ai_bench.save(html)
    await message.answer(f"{summary}\n\nОткрой и в каждом блоке выбери лучший ответ, модели — в конце:\n{link()}")


@router.message(Command("pulsecheck"))
async def cmd_pulsecheck(message: Message):
    """Пускает ли pulse.mirea.ru сервер бота (pulse_check.py) — только староста."""
    if STAROSTA_ID and not is_starosta(message.from_user.id):
        return
    import pulse_check
    await message.answer(pulse_check.text(await pulse_check.check()))



STATS_PERIODS = (7, 30, 180)


def _stats_kb(days: int) -> InlineKeyboardMarkup:
    return InlineKeyboardMarkup(inline_keyboard=[
        [InlineKeyboardButton(text=("• " if d == days else "") + {7: "7 дней", 30: "30 дней", 180: "семестр"}[d],
                              callback_data=f"stats:{d}") for d in STATS_PERIODS],
        [InlineKeyboardButton(text="👥 Кто пользуется", callback_data=f"stats:people:{days}")],
    ])


async def _send_stats(bot, chat_id: int, days: int):
    import stats
    from aiogram.types import BufferedInputFile
    png, text = await stats.report(days)
    await bot.send_photo(chat_id, BufferedInputFile(png, filename=f"stats_{days}.png"),
                         caption=text, parse_mode="HTML", reply_markup=_stats_kb(days))


@router.message(Command("stats"))
async def cmd_stats(message: Message):
    """Статистика бота картинкой (stats.py) — только староста."""
    if STAROSTA_ID and not is_starosta(message.from_user.id):
        return
    await _send_stats(message.bot, message.chat.id, 30)


@router.callback_query(F.data.startswith("stats:"))
async def cb_stats(callback: CallbackQuery):
    if STAROSTA_ID and not is_starosta(callback.from_user.id):
        await callback.answer()
        return
    parts = callback.data.split(":")
    if parts[1] == "people":
        # «кто пользуется»: имена и ники, когда и чем — без содержимого (stats.people)
        import stats
        days = int(parts[2]) if len(parts) > 2 and parts[2].isdigit() else 30
        await callback.answer()
        text = stats.people_text(await stats.people(days if days in STATS_PERIODS else 30))
        await callback.message.answer(text, parse_mode="HTML", disable_web_page_preview=True)
        return
    days = int(parts[1]) if parts[1].isdigit() else 30
    await callback.answer("Считаю…")
    await _send_stats(callback.bot, callback.message.chat.id, days if days in STATS_PERIODS else 30)
