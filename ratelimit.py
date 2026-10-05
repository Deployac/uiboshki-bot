"""
Ограничение частоты для дорогих и чувствительных действий (экран
«Безопасность»): вопросы ИИ (бесплатный лимит Gemini не сжечь одному
человеку), сдача работ и подключение СДО (не долбить СДО чужими куками
перебором). Память процесса, скользящее окно — без базы и без внешних
сервисов; после рестарта счётчики начинаются заново, это нормально.
"""

import time
from collections import defaultdict, deque

# действие → (сколько, за сколько секунд)
LIMITS = {
    "ai": (15, 60),
    "submit": (6, 600),
    "sdo_connect": (5, 600),
    "send": (20, 60),          # файлы в чат: бот не должен заваливать личку и упираться в лимиты Telegram
    "deadline": (20, 600),     # свои дедлайны
    "sdo_fresh": (3, 300),     # «обновить» баллы: каждый раз — журнал каждого предмета в СДО с IP сервера
    "site_search": (40, 60),   # сайт /about: поиск расписания без входа — по IP
    "site_target": (15, 60),
    "site_all": (300, 60),     # сайт /about: все посетители вместе — зеркало МИРЭА не долбить
}
MAX_KEYS = 5000                # ключей больше — выкинуть отжившие (IP с сайта не копятся вечно)
_hits: dict[tuple[str, int], deque] = defaultdict(deque)


def _sweep(now: float):
    stale = [k for k, q in _hits.items() if not q or now - q[-1] > LIMITS[k[0]][1]]
    for k in stale:
        del _hits[k]


def allow(action: str, user_id: int) -> bool:
    limit, window = LIMITS[action]
    now = time.monotonic()
    if len(_hits) > MAX_KEYS:
        _sweep(now)
    q = _hits[(action, user_id)]
    while q and now - q[0] > window:
        q.popleft()
    if len(q) >= limit:
        return False
    q.append(now)
    return True


def reset():
    _hits.clear()


DAY_TEXT = ("на сегодня вопросы к ИИ кончились ({n} в сутки) — бесплатный лимит ИИ один на всю "
            "группу. Завтра можно снова")


def ai(user_id: int) -> str | None:
    """Можно ли спросить ИИ: None — можно, "minute" — много подряд, "day" —
    кончился дневной лимит (config.AI_DAILY_LIMIT; 0 — без него, старосте
    не действует). Считается за последние сутки."""
    import config
    if not allow("ai", user_id):
        return "minute"
    n = config.AI_DAILY_LIMIT
    if n > 0 and not config.is_starosta(user_id):
        LIMITS["ai_day"] = (n, 86400)
        if not allow("ai_day", user_id):
            return "day"
    return None


def day_text(capital: bool = False) -> str:
    import config
    text = DAY_TEXT.format(n=config.AI_DAILY_LIMIT)
    return text[:1].upper() + text[1:] if capital else text
