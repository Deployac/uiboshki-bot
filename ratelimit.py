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
    "sdo_fresh": (3, 300),
    "site_search": (40, 60),   # сайт /about: поиск расписания без входа — по IP
    "site_target": (15, 60),     # «обновить» баллы: каждый раз — журнал каждого предмета в СДО с IP сервера
}
_hits: dict[tuple[str, int], deque] = defaultdict(deque)


def allow(action: str, user_id: int) -> bool:
    limit, window = LIMITS[action]
    now = time.monotonic()
    q = _hits[(action, user_id)]
    while q and now - q[0] > window:
        q.popleft()
    if len(q) >= limit:
        return False
    q.append(now)
    return True


def reset():
    _hits.clear()
