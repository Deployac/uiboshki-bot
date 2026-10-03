"""СДО: входы студентов (зашифрованные куки) и история баллов."""

import aiosqlite

from database._conn import connect


async def save_score_points(user_id: int, day: str, scores: dict[int, float]):
    async with connect() as db:
        await db.executemany("INSERT OR REPLACE INTO sdo_score_history (user_id, course_id, day, score) VALUES (?, ?, ?, ?)",
                             [(user_id, cid, day, sc) for cid, sc in scores.items()])
        await db.commit()


async def get_score_points(user_id: int, course_id: int, since: str) -> list[tuple[str, float]]:
    async with connect() as db:
        rows = await (await db.execute(
            "SELECT day, score FROM sdo_score_history WHERE user_id=? AND course_id=? AND day>=? ORDER BY day",
            (user_id, course_id, since))).fetchall()
        return [(d, s) for d, s in rows]


async def save_attendance_points(user_id: int, day: str, points: dict[int, tuple[float, float]]):
    """{курс: (баллы за посещаемость, максимум)} на день — последняя за день."""
    async with connect() as db:
        await db.executemany(
            "INSERT OR REPLACE INTO sdo_attendance_history (user_id, course_id, day, score, max) VALUES (?, ?, ?, ?, ?)",
            [(user_id, cid, day, sc, mx) for cid, (sc, mx) in points.items()])
        await db.commit()


async def get_attendance_points(user_id: int, course_id: int, since: str) -> list[tuple[str, float]]:
    async with connect() as db:
        rows = await (await db.execute(
            "SELECT day, score FROM sdo_attendance_history WHERE user_id=? AND course_id=? AND day>=? ORDER BY day",
            (user_id, course_id, since))).fetchall()
        return [(d, s) for d, s in rows]


async def get_attendance_marks(user_id: int, course_id: int) -> dict[str, str]:
    async with connect() as db:
        rows = await (await db.execute("SELECT day, mark FROM attendance_marks WHERE user_id=? AND course_id=?",
                                       (user_id, course_id))).fetchall()
        return {d: m for d, m in rows}


async def set_attendance_mark(user_id: int, course_id: int, day: str, mark: str | None):
    """mark — "ok" / "excused"; None — снять отметку."""
    async with connect() as db:
        if mark:
            await db.execute("INSERT OR REPLACE INTO attendance_marks (user_id, course_id, day, mark) VALUES (?, ?, ?, ?)",
                             (user_id, course_id, day, mark))
        else:
            await db.execute("DELETE FROM attendance_marks WHERE user_id=? AND course_id=? AND day=?",
                             (user_id, course_id, day))
        await db.commit()


async def get_last_scores(user_id: int) -> dict[int, float]:
    """Последняя записанная сумма баллов по каждому предмету человека."""
    async with connect() as db:
        rows = await (await db.execute(
            "SELECT h.course_id, h.score FROM sdo_score_history h JOIN (SELECT course_id, MAX(day) d "
            "FROM sdo_score_history WHERE user_id=? GROUP BY course_id) m "
            "ON h.course_id=m.course_id AND h.day=m.d WHERE h.user_id=?", (user_id, user_id))).fetchall()
        return {cid: sc for cid, sc in rows}


async def save_sdo_session(user_id: int, cookie_enc: str, next_check_at: str | None = None):
    async with connect() as db:
        await db.execute("INSERT OR REPLACE INTO sdo_sessions (user_id, cookie_enc, status, checked_at, next_check_at, jitter_left) "
                         "VALUES (?, ?, 'ok', datetime('now'), ?, 3)", (user_id, cookie_enc, next_check_at))
        await db.commit()


async def get_sdo_session(user_id: int) -> dict | None:
    async with connect() as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute("SELECT * FROM sdo_sessions WHERE user_id=?", (user_id,))
        row = await cursor.fetchone()
        return dict(row) if row else None


async def get_sdo_sessions(status: str = "ok") -> list[dict]:
    async with connect() as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute("SELECT * FROM sdo_sessions WHERE status=?", (status,))
        return [dict(r) for r in await cursor.fetchall()]


async def set_sdo_status(user_id: int, status: str):
    async with connect() as db:
        await db.execute("UPDATE sdo_sessions SET status=?, checked_at=datetime('now') WHERE user_id=?",
                         (status, user_id))
        await db.commit()


async def update_sdo_cookie(user_id: int, cookie_enc: str):
    """Перешифровка на новый ключ — без сброса расписания проверок."""
    async with connect() as db:
        await db.execute("UPDATE sdo_sessions SET cookie_enc=? WHERE user_id=?", (cookie_enc, user_id))
        await db.commit()


async def set_sdo_next_check(user_id: int, next_check_at: str, jitter_left: int):
    async with connect() as db:
        await db.execute("UPDATE sdo_sessions SET next_check_at=?, jitter_left=? WHERE user_id=?",
                         (next_check_at, jitter_left, user_id))
        await db.commit()


async def delete_sdo_session(user_id: int):
    async with connect() as db:
        await db.execute("DELETE FROM sdo_sessions WHERE user_id=?", (user_id,))
        await db.commit()


async def count_sdo_connected() -> int:
    async with connect() as db:
        return (await (await db.execute("SELECT COUNT(*) FROM sdo_sessions WHERE status='ok'")).fetchone())[0]
