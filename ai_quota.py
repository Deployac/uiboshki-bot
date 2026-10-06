"""
Вопросы к ИИ: минутный лимит (ratelimit «ai») и дневной на человека
(config.AI_DAILY_LIMIT, 0 — без него, старосте не действует).

Дневной счёт — по календарному дню МСК и в базе (settings «ai_day:<дата>»):
в памяти он обнулялся бы на каждом деплое, а «сутки назад» не совпадали с
обещанием «завтра можно снова». Считаются все настоящие вопросы — ИИ-чат,
решалка в боте, фото, конспекты; классификатор намерений («покажи
дедлайны») — только минутным лимитом: это не вопрос к ИИ. По этим же
цифрам /stats показывает «ИИ сегодня».
"""

import json

import ratelimit

MINUTE_TEXT = "слишком много вопросов подряд — подожди минуту"
DAY_TEXT = ("на сегодня вопросы к ИИ кончились ({n} в сутки) — бесплатный лимит ИИ один на всю "
            "группу. Завтра можно снова")


def _key(day=None) -> str:
    from utils import today_msk
    return f"ai_day:{(day or today_msk()).isoformat()}"


async def today() -> dict[int, int]:
    """Вопросов к ИИ сегодня по людям."""
    from database import get_setting
    try:
        raw = json.loads(await get_setting(_key()) or "{}")
    except ValueError:
        raw = {}
    return {int(k): int(v) for k, v in raw.items()}


async def summary() -> tuple[int, int]:
    """(вопросов сегодня всего, у самого активного) — одно на /stats и /status."""
    counts = await today()
    return sum(counts.values()), max(counts.values(), default=0)


async def take(user_id: int) -> bool:
    """Записать вопрос; False — дневной лимит уже исчерпан (тогда не пишем)."""
    import config
    import locks
    from database import set_setting
    async with locks.lock("ai_day"):
        counts = await today()
        n, limit = counts.get(user_id, 0), config.AI_DAILY_LIMIT
        if limit > 0 and n >= limit and not config.is_starosta(user_id):
            return False
        counts[user_id] = n + 1
        await set_setting(_key(), json.dumps({str(k): v for k, v in counts.items()}))
    return True


async def gate(user_id: int, day: bool = True) -> str | None:
    """Можно ли спросить ИИ: None — можно (и вопрос записан, если day);
    иначе "minute" или "day"."""
    if not ratelimit.allow("ai", user_id):
        return "minute"
    if day and not await take(user_id):
        return "day"
    return None


async def day_only(user_id: int) -> str | None:
    """Только дневной счёт — когда минутный уже проверен (классификатор)."""
    return None if await take(user_id) else "day"


def text(why: str, capital: bool = False) -> str:
    import config
    t = DAY_TEXT.format(n=config.AI_DAILY_LIMIT) if why == "day" else MINUTE_TEXT
    return t[:1].upper() + t[1:] if capital else t
