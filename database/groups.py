"""Группы института (этап 1): группа человека, справочник групп, подписки."""

import aiosqlite

from database._conn import connect


async def upsert_group(group_id: int, name: str, own: bool = False):
    async with connect() as db:
        await db.execute(
            "INSERT INTO groups (id, name, own) VALUES (?, ?, ?) "
            "ON CONFLICT(id) DO UPDATE SET name = excluded.name, own = MAX(own, excluded.own)",
            (group_id, name, 1 if own else 0))
        await db.commit()


async def get_group(group_id: int) -> dict | None:
    async with connect() as db:
        db.row_factory = aiosqlite.Row
        row = await (await db.execute("SELECT * FROM groups WHERE id = ?", (group_id,))).fetchone()
        return dict(row) if row else None


async def get_user_group(user_id: int) -> int | None:
    async with connect() as db:
        row = await (await db.execute("SELECT group_id FROM users WHERE user_id = ?", (user_id,))).fetchone()
        return row[0] if row else None


async def set_user_group(user_id: int, group_id: int):
    async with connect() as db:
        await db.execute("UPDATE users SET group_id = ? WHERE user_id = ?", (group_id, user_id))
        await db.commit()


async def group_counts() -> list[dict]:
    """Группы и сколько в них людей — для /stats."""
    async with connect() as db:
        rows = await (await db.execute(
            "SELECT u.group_id, COALESCE(g.name, ''), COUNT(*) FROM users u "
            "LEFT JOIN groups g ON g.id = u.group_id GROUP BY u.group_id ORDER BY COUNT(*) DESC")).fetchall()
    return [{"id": r[0], "name": r[1], "users": r[2]} for r in rows]


async def get_subscription(user_id: int) -> str | None:
    """До какой даты подписка (YYYY-MM-DD) или None."""
    async with connect() as db:
        row = await (await db.execute("SELECT until FROM subscriptions WHERE user_id = ?", (user_id,))).fetchone()
        return row[0] if row else None


async def set_subscription_until(user_id: int, until: str | None, source: str = "manual"):
    """until=None — снять подписку."""
    async with connect() as db:
        if until is None:
            await db.execute("DELETE FROM subscriptions WHERE user_id = ?", (user_id,))
        else:
            await db.execute(
                "INSERT INTO subscriptions (user_id, until, source) VALUES (?, ?, ?) "
                "ON CONFLICT(user_id) DO UPDATE SET until = excluded.until, source = excluded.source",
                (user_id, until, source))
        await db.commit()
