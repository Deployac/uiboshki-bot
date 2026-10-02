"""Расписание группы: загрузка календаря МИРЭА с кэшем и запасной копией,
готовые ответы бота (сегодня, завтра, неделя, ближайшая пара), предметы
группы. Разбор ical — schedule_events.py, оформление — schedule_format.py."""

import time
import httpx
import logging
from datetime import date, datetime, timedelta

from config import ICAL_URL, SCHEDULE_CACHE_TTL_SECONDS

from optional_subjects import unfiltered
logger = logging.getLogger(__name__)

# Разбор и оформление — в schedule_events.py и schedule_format.py (v5.0.2);
# здесь — загрузка календаря с кэшем и сборка готовых ответов. Снаружи всё
# по-старому: from schedule_parser import lessons_for_date, MONTHS_GEN, …
from schedule_format import (  # noqa: F401
    TZ, DAY_NAMES, MONTHS_GEN, DAY_SHORT, PAIR_SLOTS, format_day, format_lesson, is_self_study,
    _human_date, _keycap, _split_kind,
)
from schedule_events import (  # noqa: F401
    TEACHER_RE, parse_events_for_date, lessons_for_date, week_number, week_overview, target_weeks,
    summarize_target, list_upcoming_events, _calendar_query,
)

# ── Простой TTL-кэш сырого ical-фида ────────────────────────────────────────────
# Раньше fetch_schedule_raw() дёргался без кэша отовсюду: каждую минуту из
# check_lesson_reminders (scheduler.py), плюс из каждой команды /today, /tomorrow
# и т.д. — десятки одинаковых HTTP-запросов к стороннему серверу в минуту.
_cache_data: bytes | None = None
_cache_time: float = 0.0


# Зеркало МИРЭА иногда лежит. Тогда отдаём последний удачный календарь (из
# памяти или из базы — после перезапуска) и помним, от какого он времени:
# stale_label() → «14:20», и бот/приложение честно пишут «данные от 14:20».
_ok_at: datetime | None = None        # когда последний раз календарь скачался
_stale = False                        # сейчас отдаём сохранённое, а не свежее
_backup_hash: int | None = None


def stale_label() -> str | None:
    """None — расписание свежее; иначе «14:20» или «1 окт, 14:20»."""
    if not _stale or not _ok_at:
        return None
    t = _ok_at.astimezone(TZ)
    if t.date() == datetime.now(TZ).date():
        return f"{t:%H:%M}"
    months = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"]
    return f"{t.day} {months[t.month - 1]}, {t:%H:%M}"


def stale_note() -> str:
    lbl = stale_label()
    return f"\n\n⚠️ <i>Сайт расписания МИРЭА не отвечает — показываю сохранённое от {lbl}.</i>" if lbl else ""


async def _download() -> bytes:
    async with httpx.AsyncClient(timeout=30) as client:
        resp = await client.get(ICAL_URL)
        resp.raise_for_status()
        if b"BEGIN:VCALENDAR" not in resp.content[:512]:
            raise ValueError("зеркало ответило не календарём")   # страница ошибки с кодом 200
        return resp.content


async def _save_backup(data: bytes):
    global _backup_hash
    h = hash(data)
    if h == _backup_hash:
        return
    try:
        from database import save_schedule_backup
        await save_schedule_backup(data, _ok_at.isoformat())
        _backup_hash = h
    except Exception as e:
        logger.info(f"Копия расписания не сохранилась: {e}")


async def fetch_schedule_raw(force: bool = False) -> bytes:
    global _cache_data, _cache_time, _ok_at, _stale
    now = time.monotonic()
    if not force and _cache_data is not None and (now - _cache_time) < SCHEDULE_CACHE_TTL_SECONDS:
        return _cache_data
    try:
        data = await _download()
    except Exception as e:
        if _cache_data is None:
            try:
                from database import load_schedule_backup
                saved = await load_schedule_backup()
            except Exception as be:
                logger.warning(f"запасная копия расписания не прочиталась: {be!r}")
                saved = None
            if not saved:
                raise
            _cache_data, _ok_at = saved[0], datetime.fromisoformat(saved[1])
        logger.warning(f"Расписание: зеркало не отвечает ({type(e).__name__}) — отдаю сохранённое")
        _stale = True
        # повторить попытку через минуту, а не ждать весь TTL
        _cache_time = now - SCHEDULE_CACHE_TTL_SECONDS + 60
        return _cache_data
    _cache_data, _cache_time, _ok_at, _stale = data, now, datetime.now(TZ), False
    await _save_backup(data)
    return _cache_data


async def get_today_schedule() -> str:
    try:
        raw   = await fetch_schedule_raw()
        now   = datetime.now(TZ)
        return format_day(parse_events_for_date(raw, now.date()), now.date(), now=now) + stale_note()
    except Exception as e:
        logger.error(f"Ошибка расписания: {e}")
        return "⚠️ Не удалось загрузить расписание."


async def get_tomorrow_schedule() -> str:
    try:
        raw      = await fetch_schedule_raw()
        tomorrow = datetime.now(TZ).date() + timedelta(days=1)
        return format_day(parse_events_for_date(raw, tomorrow), tomorrow) + stale_note()
    except Exception as e:
        logger.error(f"Ошибка расписания: {e}")
        return "⚠️ Не удалось загрузить расписание."


_subjects_cache: dict[tuple, list[str]] = {}


async def get_group_subjects(days_back: int = 14, days_ahead: int = 28) -> list[str]:
    """Настоящие названия предметов группы (без «ЛК/ПР») из её расписания —
    для кнопок выбора предмета при загрузке файлов и в решалке, чтобы файлы
    лекций и решалка говорили на одном языке, а не «Математика» против
    «Основы бизнес-анализа в ИТ-сфере». Пустой список, если расписание
    не загрузилось."""
    try:
        raw = await fetch_schedule_raw()
    except Exception as e:
        logger.warning(f"get_group_subjects: {e}")
        return []
    today = datetime.now(TZ).date()
    key = (id(raw), today, days_back, days_ahead)
    if key in _subjects_cache:
        return _subjects_cache[key]
    start = datetime.combine(today - timedelta(days=days_back), datetime.min.time(), TZ)
    end = datetime.combine(today + timedelta(days=days_ahead), datetime.min.time(), TZ)
    names = set()
    for component in _calendar_query(raw).between(start, end):
        summary = str(component.get("SUMMARY", ""))
        if not summary or summary.strip().endswith("неделя"):
            continue
        title, _, _ = _split_kind(summary)
        if title:
            names.add(title)
    _subjects_cache.clear()
    _subjects_cache[key] = sorted(names)
    return _subjects_cache[key]


@unfiltered
def format_target_schedule(raw: bytes, target_type: int, days: int = 14) -> str:
    """Расписание найденного преподавателя/группы/аудитории на days дней
    вперёд, пустые дни пропускаются. У преподавателя и аудитории в строке —
    группы, у группы — преподаватель (target_type как в API МИРЭА: 1 группа,
    2 преподаватель, 3 аудитория)."""
    extra = "teacher" if target_type == 1 else "groups"
    today = datetime.now(TZ).date()
    blocks = []
    for i in range(days):
        d = today + timedelta(days=i)
        events = parse_events_for_date(raw, d)
        if events:
            blocks.append(format_day(events, d, compact=True, extra=extra))
    if not blocks:
        return f"Пар в ближайшие {days} дней нет."
    return "\n\n".join(blocks)


def _format_week(raw: bytes, monday: date, label: str) -> str:
    saturday = monday + timedelta(days=5)
    span = (f"{monday.day}–{_human_date(saturday)}" if monday.month == saturday.month
            else f"{_human_date(monday)} – {_human_date(saturday)}")
    days = [format_day(parse_events_for_date(raw, monday + timedelta(days=i)), monday + timedelta(days=i), compact=True)
            for i in range(6)]
    return f"📆 <b>{label}</b> · {span}\n\n" + "\n\n".join(days)


async def get_week_schedule() -> str:
    try:
        raw   = await fetch_schedule_raw()
        today = datetime.now(TZ).date()
        monday = today - timedelta(days=today.weekday())

        return _format_week(raw, monday, "Эта неделя")
    except Exception as e:
        logger.error(f"Ошибка расписания: {e}")
        return "⚠️ Не удалось загрузить расписание."


async def get_next_week_schedule() -> str:
    try:
        raw   = await fetch_schedule_raw()
        today = datetime.now(TZ).date()
        days_until_monday = (7 - today.weekday()) % 7 or 7
        next_monday = today + timedelta(days=days_until_monday)

        return _format_week(raw, next_monday, "Следующая неделя")
    except Exception as e:
        logger.error(f"Ошибка расписания: {e}")
        return "⚠️ Не удалось загрузить расписание."


async def get_next_lesson() -> str:
    try:
        raw  = await fetch_schedule_raw()
        now  = datetime.now(TZ)
        today = now.date()
        events = parse_events_for_date(raw, today)

        for e in events:
            if e["time_start"] and e["time_start"] > now:
                delta = e["time_start"] - now
                mins  = int(delta.total_seconds() // 60)
                hrs   = mins // 60
                mins  = mins % 60
                time_left = f"{hrs} ч {mins} мин" if hrs else f"{mins} мин"
                num = _keycap(events.index(e) + 1)
                return (
                    f"⏭ <b>Следующая пара — через {time_left}</b>\n\n"
                    + format_lesson(e, num)
                )

        tomorrow = today + timedelta(days=1)
        t_events = parse_events_for_date(raw, tomorrow)
        if t_events:
            e = t_events[0]
            return (
                "✅ На сегодня пары закончились!\n\n"
                "<b>Завтра первая пара:</b>\n"
                + format_lesson(e, _keycap(1))
            )
        return "✅ Пар больше нет ни сегодня, ни завтра!"
    except Exception as e:
        logger.error(f"Ошибка: {e}")
        return "⚠️ Не удалось получить расписание."


async def get_first_lesson_today() -> dict | None:
    try:
        raw    = await fetch_schedule_raw()
        today  = datetime.now(TZ).date()
        events = parse_events_for_date(raw, today)
        for e in events:
            if e["time_start"]:
                return e
        return None
    except Exception:
        return None
