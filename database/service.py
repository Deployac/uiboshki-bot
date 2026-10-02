"""Служебное: история решалки, очистка семестра, события для /stats."""

import aiosqlite

from database._conn import connect


# ── Solver history ────────────────────────────────────────────────────────────

async def add_solver_history(user_id: int, task: str, answer: str, subject: str = ""):
    async with connect() as db:
        await db.execute("""
            INSERT INTO solver_history (user_id, task_text, answer, subject)
            VALUES (?, ?, ?, ?)
        """, (user_id, task[:500], answer[:2000], subject))
        await db.commit()


async def get_solver_history(user_id: int, limit=5) -> list[dict]:
    async with connect() as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute("""
            SELECT * FROM solver_history WHERE user_id=?
            ORDER BY created_at DESC LIMIT ?
        """, (user_id, limit))
        return [dict(r) for r in await cursor.fetchall()]


# ── Очистка семестра (для /clearsem) ────────────────────────────────────────
# Сносит "живые" данные конкретного семестра — дедлайны, доску ДЗ, файлы,
# голосования. НЕ трогает: подписки/настройки пользователей, историю решений
# решалки, заметки на пары, ленту "Подслушано", zam_id в settings —
# это либо личные настройки, либо архив, который не привязан к семестру.
async def clear_semester_data():
    async with connect() as db:
        # file_text — вместе с files: иначе извлечённый текст всех лекций
        # семестра навсегда остаётся в базе сиротами (см. delete_file).
        for table in ("deadlines", "deadline_done", "homework", "files", "file_text", "vote_answers", "votes"):
            try:
                await db.execute(f"DELETE FROM {table}")
            except Exception:
                pass  # таблицы homework/votes создаются лениво — их может не быть
        await db.commit()


async def add_event(user_id: int, kind: str):
    async with connect() as db:
        await db.execute("INSERT INTO events (user_id, kind) VALUES (?, ?)", (user_id, kind))
        await db.commit()


async def events_since(days: int) -> list[tuple[int, str, str]]:
    async with connect() as db:
        cursor = await db.execute(
            "SELECT user_id, kind, at FROM events WHERE at >= datetime('now', ?)", (f"-{int(days)} days",))
        return await cursor.fetchall()


async def purge_events(keep_days: int = 180):
    async with connect() as db:
        await db.execute("DELETE FROM events WHERE at < datetime('now', ?)", (f"-{int(keep_days)} days",))
        await db.commit()
