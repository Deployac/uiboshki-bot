"""Подписки на веб-пуши (этап 2 (г), delivery.py): устройство = endpoint."""

import aiosqlite

from database._conn import connect


async def save_push_sub(user_id: int, endpoint: str, p256dh: str, auth: str, device: str = ""):
    async with connect() as db:
        await db.execute(
            "INSERT INTO push_subs (endpoint, user_id, p256dh, auth, device) VALUES (?, ?, ?, ?, ?) "
            "ON CONFLICT(endpoint) DO UPDATE SET user_id = excluded.user_id, p256dh = excluded.p256dh, "
            "auth = excluded.auth, device = excluded.device",
            (endpoint, user_id, p256dh, auth, device[:120]))
        await db.commit()


async def get_push_subs(user_id: int) -> list[dict]:
    async with connect() as db:
        db.row_factory = aiosqlite.Row
        rows = await (await db.execute("SELECT * FROM push_subs WHERE user_id = ?", (user_id,))).fetchall()
        return [dict(r) for r in rows]


async def delete_push_sub(endpoint: str, user_id: int | None = None) -> int:
    sql, args = "DELETE FROM push_subs WHERE endpoint = ?", [endpoint]
    if user_id is not None:
        sql, args = sql + " AND user_id = ?", args + [user_id]
    async with connect() as db:
        cur = await db.execute(sql, args)
        await db.commit()
        return cur.rowcount
