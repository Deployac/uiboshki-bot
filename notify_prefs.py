"""
Конструктор уведомлений (WebApp → ☰ Ещё → Уведомления): что присылать и в
какие дни. Хранится JSON в users.notify; чего там нет — берётся из DEFAULTS
(они повторяют старое поведение: всё включено, каждый день). Общий выключатель
— по-прежнему users.subscribed, время напоминания о паре — reminder_minutes.

Корпус: у пар МИРЭА место вида «В-328 (В-78)» — корпус в скобках. «Свой»
корпус группы — самый частый в её календаре; если сегодня пары в другом,
утренняя рассылка подсвечивает это («сегодня пары на МП-1, не на В-78»).
"""

import json
import re
from collections import Counter

ALL_DAYS = [0, 1, 2, 3, 4, 5, 6]
REMINDER_CHOICES = (5, 10, 15, 30)

DEFAULTS = {
    "morning": True, "morning_days": ALL_DAYS, "weather": True, "campus": True, "skip_empty": False,
    "lessons": True, "lesson_days": ALL_DAYS,
    "deadlines": True, "deadline_days": ALL_DAYS,
}
DAYS_KEY = {"morning": "morning_days", "lessons": "lesson_days", "deadlines": "deadline_days"}
_BOOLS = [k for k, v in DEFAULTS.items() if isinstance(v, bool)]
_DAYS = [k for k in DEFAULTS if k.endswith("_days")]


def merge(raw: str | dict | None) -> dict:
    """Сохранённое поверх умолчаний; мусор и лишние ключи отбрасываются."""
    if isinstance(raw, str):
        try:
            raw = json.loads(raw)
        except ValueError:
            raw = {}
    raw = raw if isinstance(raw, dict) else {}
    out = {k: (list(v) if isinstance(v, list) else v) for k, v in DEFAULTS.items()}
    for k in _BOOLS:
        if isinstance(raw.get(k), bool):
            out[k] = raw[k]
    for k in _DAYS:
        v = raw.get(k)
        if isinstance(v, list):
            out[k] = sorted({d for d in v if isinstance(d, int) and not isinstance(d, bool) and 0 <= d <= 6})
    return out


def allowed(prefs: dict, kind: str, weekday: int) -> bool:
    """kind: morning / lessons / deadlines — включено и сегодня его день."""
    return bool(prefs.get(kind)) and weekday in prefs.get(DAYS_KEY[kind], [])


async def get(user_id: int) -> dict:
    from database import get_user
    user = await get_user(user_id) or {}
    return merge(user.get("notify"))


# ── корпус ───────────────────────────────────────────────────────────────────

_CAMPUS = re.compile(r"\(([^()]{1,12})\)\s*$")


def campus_of(location: str | None) -> str | None:
    m = _CAMPUS.search((location or "").strip())
    return m.group(1).strip() if m else None


def home_campus(raw: bytes | str) -> str | None:
    """Самый частый корпус в календаре группы."""
    text = raw.decode("utf-8", "ignore") if isinstance(raw, bytes) else raw
    text = re.sub(r"\r?\n[ \t]", "", text)            # развернуть перенесённые строки ical
    counts = Counter(c for c in (campus_of(loc.replace("\\,", ",")) for loc in
                                 re.findall(r"^LOCATION[^:]*:(.*)$", text, re.M)) if c)
    return counts.most_common(1)[0][0] if counts else None


def campus_note(events: list[dict], home: str | None) -> str:
    """Строка для утренней рассылки, если сегодня пары не в своём корпусе."""
    if not home:
        return ""
    other = [(e.get("time_start"), campus_of(e.get("location"))) for e in events]
    other = [(t, c) for t, c in other if c and c != home]
    if not other:
        return ""
    names = sorted({c for _, c in other})
    known = [c for c in (campus_of(e.get("location")) for e in events) if c]
    if len(other) == len(known):
        return f"📍 <b>Сегодня пары на {', '.join(names)}</b> — не на {home}"
    first = min((t for t, _ in other if t), default=None)
    when = f" с {first:%H:%M}" if first else ""
    return f"📍 <b>Сегодня часть пар на {', '.join(names)}</b>{when} — не только на {home}"
