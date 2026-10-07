"""Расписание: своё (главная WebApp, дни, недели), предметы по выбору, поиск
и расписание любой группы/преподавателя/аудитории МИРЭА, закреплённые,
заметки к парам и картинки расписания для inline-режима (/card)."""

import logging
import re

from fastapi import APIRouter, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel

from webapp.deps import CurrentUser

logger = logging.getLogger(__name__)

router = APIRouter()


# ── Картинки расписания для inline-режима ───────────────────────────────────
# Telegram забирает картинку по URL сам, без initData, поэтому ссылка
# подписана (schedule_card.sign). Готовые картинки — в памяти на 10 минут.
_card_cache: dict[str, tuple[float, bytes]] = {}


@router.get("/card/{key}.jpg")
async def schedule_card_image(key: str, sig: str = "", thumb: int = 0):
    import asyncio
    import time
    from datetime import datetime
    import schedule_card
    from config import BOT_USERNAME, GROUP_NAME
    from utils import TZ
    parsed = schedule_card.parse_key(key, sig)
    if not parsed:
        raise HTTPException(403, "Неверная ссылка")
    hit = _card_cache.get(key)
    if hit and hit[0] > time.time():
        return _card_response(hit[1], thumb)
    kind, target_type, target_id = parsed
    now = datetime.now(TZ)
    if kind == "target":
        import schedule_index
        from mirea_schedule_api import fetch_ical
        raw = await fetch_ical(target_id, target_type)
        if raw is None:
            raise HTTPException(502, "Расписание не загрузилось")
        title = await schedule_index.get_title(target_type, target_id) or "Расписание"
        data = await asyncio.to_thread(schedule_card.build_target, raw, title, now, BOT_USERNAME)
    else:
        from schedule_parser import fetch_schedule_raw
        raw = await fetch_schedule_raw()
        data = await asyncio.to_thread(schedule_card.build_own, raw, kind, now, GROUP_NAME, BOT_USERNAME)
    if len(_card_cache) > 200:
        _card_cache.clear()
    _card_cache[key] = (time.time() + 600, data)
    return _card_response(data, thumb)


def _card_response(data: bytes, thumb: int) -> Response:
    """Картинка целиком или маленькое превью (inline: thumbnail_url — свой адрес)."""
    if thumb:
        import schedule_card
        data = schedule_card.thumbnail(data)
    return Response(data, media_type="image/jpeg")


# ── Расписание ───────────────────────────────────────────────────────────────

async def _user_gid(user: dict) -> int | None:
    from database import get_user_group
    return await get_user_group(user["id"])


@router.get("/api/schedule/today")
async def api_schedule_today(user: dict = CurrentUser):
    from schedule_parser import get_today_schedule
    from handlers.schedule import _notes_block
    from utils import today_msk
    html = await get_today_schedule(await _user_gid(user))
    html += await _notes_block(today_msk().isoformat(), await _user_gid(user))
    return {"html": html}


@router.get("/api/schedule/tomorrow")
async def api_schedule_tomorrow(user: dict = CurrentUser):
    from schedule_parser import get_tomorrow_schedule
    return {"html": await get_tomorrow_schedule(await _user_gid(user))}


@router.get("/api/schedule/week")
async def api_schedule_week(user: dict = CurrentUser):
    from schedule_parser import get_week_schedule
    return {"html": await get_week_schedule(await _user_gid(user))}


@router.get("/api/schedule/next")
async def api_schedule_next(user: dict = CurrentUser):
    from schedule_parser import get_next_lesson
    return {"html": await get_next_lesson(await _user_gid(user))}


# ── Главная WebApp: структурой, а не готовым HTML ───────────────────────────

WEEKDAYS_RU = ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"]


def _day_label(d) -> dict:
    from schedule_parser import MONTHS_GEN
    return {"date": d.isoformat(), "weekday": WEEKDAYS_RU[d.weekday()],
            "label": f"{d.day} {MONTHS_GEN[d.month - 1]}"}


@router.get("/api/today")
async def api_today(user: dict = CurrentUser):
    """Всё для главной одним запросом: пары сегодня со статусами, ближайшая
    пара (или завтрашняя первая), погода строкой, дедлайны (сколько и
    ближайшие три), заметки к парам."""
    import asyncio
    from datetime import datetime, timedelta, date as date_cls
    from database import get_active_deadlines, get_lesson_notes
    from handlers.schedule import _clip
    from handlers.weather import get_weather_for_morning
    from schedule_parser import lessons_for_date, raw_for_user
    from utils import TZ

    # погода (кэш 20 мин, а без него — внешний запрос) — параллельно с расписанием
    weather_task = asyncio.create_task(get_weather_for_morning())
    now = datetime.now(TZ)
    today = now.date()
    lessons, tomorrow_first, schedule_ok, campus = [], None, True, ""
    try:
        raw = await raw_for_user(user["id"])
        lessons = lessons_for_date(raw, today, now=now)
        tomorrow = lessons_for_date(raw, today + timedelta(days=1))
        tomorrow_first = tomorrow[0] if tomorrow else None
        import notify_prefs        # «сегодня пары на МП-1, не на В-78»
        from schedule_parser import parse_events_for_date
        campus = re.sub(r"<[^>]+>|📍 ", "", notify_prefs.campus_note(parse_events_for_date(raw, today),
                                                                    notify_prefs.home_campus(raw)))
    except Exception as e:
        logger.warning(f"api_today: расписание недоступно: {e}")
        schedule_ok = False

    try:
        weather = await weather_task
    except Exception:
        weather = ""

    items = await get_active_deadlines(user["id"])
    soon = []
    for d in items[:3]:
        days = (date_cls.fromisoformat(d["due_date"]) - today).days
        soon.append({"id": d["id"], "subject": d["subject"], "due_date": d["due_date"],
                     "due_time": d.get("due_time") or "", "days": days})
    from database.groups import viewer_group
    notes = await get_lesson_notes(today.isoformat(), await viewer_group(user["id"]))
    return {
        **_day_label(today), "now": now.isoformat(), "hour": now.hour,
        "lessons": lessons, "tomorrow_first": tomorrow_first, "schedule_ok": schedule_ok,
        "weather": weather, "campus": campus, "stale": await _stale_for(user["id"]),
        "deadlines": {"active": len(items), "soon": soon},
        "notes": [{"subject": n.get("subject") or "", "text": _clip(n["text"])} for n in notes],
    }


def _stale_label() -> str | None:
    from schedule_parser import stale_label
    return stale_label()


async def _stale_for(user_id: int) -> str | None:
    """«Данные от 14:20» — только у своей группы (у неё запасная копия в базе)."""
    import groups
    from database import get_user_group
    gid = await get_user_group(user_id)
    return None if gid and gid != groups.home_id() else _stale_label()


class OptionalAnswer(BaseModel):
    subject: str
    attend: bool


@router.get("/api/optional")
async def api_optional(user: dict = CurrentUser):
    """Предметы по выбору: о каких спросить (pending) и что уже ответил."""
    from config import OPTIONAL_SUBJECTS
    from database import get_optional_answers
    from optional_subjects import pending_for
    answers = await get_optional_answers(user["id"])
    return {"pending": await pending_for(user["id"]),
            "answers": {s: answers[s] for s in OPTIONAL_SUBJECTS if s in answers}}


@router.post("/api/optional")
async def api_optional_set(body: OptionalAnswer, user: dict = CurrentUser):
    from config import OPTIONAL_SUBJECTS
    from database import set_optional_answer
    if body.subject not in OPTIONAL_SUBJECTS:
        raise HTTPException(status_code=400, detail="не предмет по выбору")
    await set_optional_answer(user["id"], body.subject, body.attend)
    return {"ok": True}


@router.get("/api/day")
async def api_day(date: str, user: dict = CurrentUser):
    """Пары любого дня (для выбора дня недели на главной)."""
    from datetime import date as date_cls, datetime
    from schedule_parser import lessons_for_date, raw_for_user
    from utils import TZ
    try:
        d = date_cls.fromisoformat(date)
    except ValueError:
        raise HTTPException(status_code=400, detail="дата в формате ГГГГ-ММ-ДД")
    try:
        raw = await raw_for_user(user["id"])
    except Exception:
        raise HTTPException(status_code=502, detail="расписание сейчас недоступно")
    now = datetime.now(TZ)
    return {**_day_label(d), "lessons": lessons_for_date(raw, d, now=now if d == now.date() else None)}


@router.get("/api/week")
async def api_week(start: str, user: dict = CurrentUser):
    """Номер учебной недели и точки пар под днями (пн–сб от start)."""
    from datetime import date as date_cls
    from schedule_parser import raw_for_user, week_overview
    try:
        monday = date_cls.fromisoformat(start)
    except ValueError:
        raise HTTPException(status_code=400, detail="дата в формате ГГГГ-ММ-ДД")
    try:
        raw = await raw_for_user(user["id"])
    except Exception:
        raise HTTPException(status_code=502, detail="расписание сейчас недоступно")
    return week_overview(raw, monday)


# ── Поиск расписания преподавателя / группы / аудитории ─────────────────────
# Свой справочник (schedule_index.py, собран с зеркала english.mirea.ru):
# официальный поиск МИРЭА из-за рубежа не отвечает. Пока справочник
# собирается — пробуем официальный, иначе честно говорим «ещё собирается».

@router.get("/api/search")
async def api_search(q: str = "", type: int = 0, user: dict = CurrentUser):
    import schedule_index
    from mirea_schedule_api import _official_search
    types = (type,) if type in schedule_index.TYPES else schedule_index.TYPES
    q = q.strip()
    if len(q) < 2:
        return {"items": [], "ready": await schedule_index.is_ready()}
    items = await schedule_index.search(q, types, limit=30)
    ready = await schedule_index.is_ready()
    if items:
        from mirea_schedule_api import add_hints_for_namesakes
        hinted = await add_hints_for_namesakes(
            [{"id": i["id"], "fullTitle": i["title"], "scheduleTarget": i["type"]} for i in items])
        items = [{"type": h["scheduleTarget"], "id": h["id"], "title": h["fullTitle"],
                  **({"hint": h["hint"]} if h.get("hint") else {})} for h in hinted]
    if not items and not ready:
        for t in types:
            try:
                items += [{"type": t, "id": d["id"], "title": d["fullTitle"]}
                          for d in await _official_search(q, t, 10)]
            except Exception:
                break
    return {"items": items, "ready": ready}


TARGET_WEEKS = 8


@router.get("/api/target/{target_type}/{target_id}")
async def api_target(target_type: int, target_id: int, user: dict = CurrentUser):
    """Расписание группы/преподавателя/аудитории на TARGET_WEEKS недель с
    текущей (в воскресенье — со следующей): WebApp рисует его так же, как
    главную, — недели, точки под днями, карточки пар."""
    from datetime import datetime, timedelta
    from database import get_pins
    from mirea_schedule_api import get_baseinfo, fetch_ical
    from schedule_parser import target_weeks
    from utils import TZ
    if target_type not in (1, 2, 3):
        raise HTTPException(status_code=404, detail="нет такого типа")
    info = await get_baseinfo(target_id, target_type)
    ical = await fetch_ical(target_id, target_type)
    stale = None
    if ical is None and _own_group(target_type, target_id):
        # своя группа — из сохранённой копии, как на главной (дизайн-ревью, п. 6)
        from schedule_parser import fetch_schedule_raw, stale_label
        try:
            ical, stale = await fetch_schedule_raw(), stale_label()
        except Exception as e:
            logger.info(f"api_target: и копии своей группы нет: {e!r}")
    if ical is None:
        raise HTTPException(status_code=502, detail="расписание МИРЭА сейчас недоступно")
    now = datetime.now(TZ)
    today = now.date()
    monday = today - timedelta(days=today.weekday()) + timedelta(days=7 if today.weekday() == 6 else 0)
    try:
        weeks = target_weeks(ical, monday, TARGET_WEEKS, now=now)
    except Exception as e:      # обрывок календаря — не 500, а «недоступно»
        logger.warning(f"api_target: календарь {target_type}/{target_id} не разобрался: {e!r}")
        raise HTTPException(status_code=502, detail="расписание МИРЭА сейчас недоступно")
    pinned = any(p["type"] == target_type and p["id"] == target_id for p in await get_pins(user["id"]))
    return {
        "type": target_type, "id": target_id,
        "title": info["fullTitle"] if info else str(target_id),
        "pinned": pinned,
        "today": today.isoformat(),
        "weeks": weeks,
        "stale": stale,
    }


def _own_group(target_type: int, target_id: int) -> bool:
    """Это календарь самой группы бота (ICAL_URL …/ical/1/4928)?"""
    from config import ICAL_URL
    m = re.search(r"/ical/(\d+)/(\d+)", ICAL_URL or "")
    return bool(m) and (int(m.group(1)), int(m.group(2))) == (target_type, target_id)


# ── Закреплённые группы / преподаватели / аудитории ─────────────────────────

class PinBody(BaseModel):
    title: str


@router.get("/api/pins")
async def api_pins(user: dict = CurrentUser):
    from database import get_pins
    return {"items": await get_pins(user["id"])}


@router.put("/api/pins/{target_type}/{target_id}")
async def api_pin(target_type: int, target_id: int, body: PinBody, user: dict = CurrentUser):
    from database import MAX_PINS, pin_target
    title = body.title.strip()[:120]
    if target_type not in (1, 2, 3) or not title:
        raise HTTPException(status_code=400, detail="нужны тип цели и название")
    if not await pin_target(user["id"], target_type, target_id, title):
        raise HTTPException(status_code=400, detail=f"закрепить можно до {MAX_PINS}")
    return {"ok": True}


@router.delete("/api/pins/{target_type}/{target_id}")
async def api_unpin(target_type: int, target_id: int, user: dict = CurrentUser):
    from database import unpin_target
    await unpin_target(user["id"], target_type, target_id)
    return {"ok": True}


# ── Заметки к парам ──────────────────────────────────────────────────────────

@router.get("/api/notes")
async def api_notes(date: str = "", user: dict = CurrentUser):
    from database import get_lesson_notes
    from utils import today_msk
    from database.groups import viewer_group
    date_str = date or today_msk().isoformat()
    items = await get_lesson_notes(date_str, await viewer_group(user["id"]))
    return {"date": date_str, "items": items}
