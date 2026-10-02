"""Пользователи: регистрация, подписка, уведомления, календарный токен, предметы по выбору."""

import secrets

import aiosqlite

from database._conn import connect


# ── Users ─────────────────────────────────────────────────────────────────────

async def upsert_user(user_id: int, username: str, full_name: str):
    async with connect() as db:
        await db.execute("""
            INSERT INTO users (user_id, username, full_name)
            VALUES (?, ?, ?)
            ON CONFLICT(user_id) DO UPDATE SET
                username  = excluded.username,
                full_name = excluded.full_name
        """, (user_id, username, full_name))
        await db.commit()


async def get_all_subscribed_users() -> list[int]:
    async with connect() as db:
        cursor = await db.execute("SELECT user_id FROM users WHERE subscribed = 1")
        return [r[0] for r in await cursor.fetchall()]


async def get_reminder_users() -> list[dict]:
    """Подписчики с их настройками уведомлений — одним запросом (напоминания
    о парах проверяются раз в минуту, по запросу на человека — лишнее)."""
    async with connect() as db:
        cursor = await db.execute("SELECT user_id, notify FROM users WHERE subscribed = 1")
        return [{"user_id": r[0], "notify": r[1]} for r in await cursor.fetchall()]


async def get_all_optional_answers() -> dict[int, dict[str, bool]]:
    async with connect() as db:
        out: dict[int, dict[str, bool]] = {}
        for uid, subject, attend in await (await db.execute(
                "SELECT user_id, subject, attend FROM optional_subjects")).fetchall():
            out.setdefault(uid, {})[subject] = bool(attend)
        return out


async def set_notify(user_id: int, prefs: dict):
    import json
    async with connect() as db:
        await db.execute("UPDATE users SET notify = ? WHERE user_id = ?",
                         (json.dumps(prefs, ensure_ascii=False), user_id))
        await db.commit()


# ── Персональные ссылки на ICS-календарь ────────────────────────────────────
# Токен — случайная непредсказуемая строка (не user_id), чтобы ссылку нельзя
# было подобрать перебором и увидеть чужое расписание/ДЗ. Ссылка привязана к
# конкретному студенту, но сам .ics-эндпоинт не требует initData (календарные
# приложения не умеют слать кастомные заголовки при периодическом опросе
# webcal-подписки) — секретность держится на непредсказуемости токена, как у
# большинства calendar-share ссылок (Google/Apple делают так же).

async def get_or_create_calendar_token(user_id: int) -> str:
    async with connect() as db:
        cursor = await db.execute("SELECT calendar_token FROM users WHERE user_id = ?", (user_id,))
        row = await cursor.fetchone()
        if row and row[0]:
            return row[0]
        token = secrets.token_urlsafe(24)
        # INSERT ... ON CONFLICT — а не UPDATE — потому что get_or_create_calendar_token
        # может быть вызвана до /start (юзер ещё не встречался upsert_user), тогда
        # обычный UPDATE тихо обновит 0 строк и токен нигде не сохранится.
        await db.execute("""
            INSERT INTO users (user_id, calendar_token) VALUES (?, ?)
            ON CONFLICT(user_id) DO UPDATE SET calendar_token = excluded.calendar_token
        """, (user_id, token))
        await db.commit()
        return token


async def get_user_by_calendar_token(token: str) -> dict | None:
    if not token:
        return None
    async with connect() as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute("SELECT * FROM users WHERE calendar_token = ?", (token,))
        row = await cursor.fetchone()
        return dict(row) if row else None


async def set_subscription(user_id: int, value: int):
    async with connect() as db:
        await db.execute("UPDATE users SET subscribed = ? WHERE user_id = ?", (value, user_id))
        await db.commit()


async def get_reminder_minutes(user_id: int) -> int:
    async with connect() as db:
        cursor = await db.execute("SELECT reminder_minutes FROM users WHERE user_id = ?", (user_id,))
        row = await cursor.fetchone()
        return row[0] if row else 15


async def set_reminder_minutes(user_id: int, minutes: int):
    async with connect() as db:
        await db.execute("UPDATE users SET reminder_minutes = ? WHERE user_id = ?", (minutes, user_id))
        await db.commit()


async def get_user(user_id: int) -> dict | None:
    async with connect() as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute("SELECT * FROM users WHERE user_id = ?", (user_id,))
        row = await cursor.fetchone()
        return dict(row) if row else None


async def get_optional_answers(user_id: int) -> dict[str, bool]:
    """Предметы по выбору, на которые человек уже ответил: предмет → ходит ли."""
    async with connect() as db:
        cursor = await db.execute("SELECT subject, attend FROM optional_subjects WHERE user_id=?", (user_id,))
        return {r[0]: bool(r[1]) for r in await cursor.fetchall()}


async def set_optional_answer(user_id: int, subject: str, attend: bool):
    async with connect() as db:
        await db.execute("INSERT OR REPLACE INTO optional_subjects (user_id, subject, attend) VALUES (?, ?, ?)",
                         (user_id, subject, int(attend)))
        await db.commit()


async def count_users() -> int:
    async with connect() as db:
        return (await (await db.execute("SELECT COUNT(*) FROM users")).fetchone())[0]
