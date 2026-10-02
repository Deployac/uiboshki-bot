"""Группа: голосования, лента «Подслушано», заметки к парам."""

import aiosqlite

from database._conn import connect


# ── Votes ─────────────────────────────────────────────────────────────────────

async def create_vote(question: str, created_by: int) -> int:
    async with connect() as db:
        cursor = await db.execute("""
            INSERT INTO votes (question, created_by) VALUES (?, ?)
        """, (question, created_by))
        await db.commit()
        return cursor.lastrowid


async def get_active_vote() -> dict | None:
    async with connect() as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute("SELECT * FROM votes WHERE active=1 ORDER BY created_at DESC LIMIT 1")
        row = await cursor.fetchone()
        return dict(row) if row else None


async def add_vote_answer(vote_id: int, user_id: int, answer: str):
    async with connect() as db:
        await db.execute("""
            INSERT OR REPLACE INTO vote_answers (vote_id, user_id, answer) VALUES (?, ?, ?)
        """, (vote_id, user_id, answer))
        await db.commit()


async def get_vote_results(vote_id: int) -> dict:
    async with connect() as db:
        cursor = await db.execute("""
            SELECT answer, COUNT(*) as cnt FROM vote_answers WHERE vote_id=? GROUP BY answer
        """, (vote_id,))
        rows = await cursor.fetchall()
        return {r[0]: r[1] for r in rows}


async def close_vote(vote_id: int):
    async with connect() as db:
        await db.execute("UPDATE votes SET active=0 WHERE id=?", (vote_id,))
        await db.commit()


# ── Лента "Подслушано" ────────────────────────────────────────────────────────

async def get_last_feed_post_time(author_id: int) -> str | None:
    async with connect() as db:
        cursor = await db.execute("""
            SELECT created_at FROM feed_posts
            WHERE author_id=? AND deleted=0
            ORDER BY created_at DESC LIMIT 1
        """, (author_id,))
        row = await cursor.fetchone()
        return row[0] if row else None


async def add_feed_post(text: str, photo_file_id: str, author_id: int) -> int:
    async with connect() as db:
        cursor = await db.execute("""
            INSERT INTO feed_posts (text, photo_file_id, author_id) VALUES (?, ?, ?)
        """, (text, photo_file_id, author_id))
        await db.commit()
        return cursor.lastrowid


async def set_feed_post_message_id(post_id: int, message_id: int):
    async with connect() as db:
        await db.execute("UPDATE feed_posts SET message_id=? WHERE id=?", (message_id, post_id))
        await db.commit()


async def get_feed_post(post_id: int) -> dict | None:
    async with connect() as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute("SELECT * FROM feed_posts WHERE id=?", (post_id,))
        row = await cursor.fetchone()
        return dict(row) if row else None


async def delete_feed_post(post_id: int):
    async with connect() as db:
        await db.execute("UPDATE feed_posts SET deleted=1 WHERE id=?", (post_id,))
        await db.commit()


async def set_feed_reaction(post_id: int, user_id: int, emoji: str):
    async with connect() as db:
        await db.execute("""
            INSERT OR REPLACE INTO feed_reactions (post_id, user_id, emoji) VALUES (?, ?, ?)
        """, (post_id, user_id, emoji))
        await db.commit()


async def get_feed_reaction_counts(post_id: int) -> dict:
    async with connect() as db:
        cursor = await db.execute("""
            SELECT emoji, COUNT(*) as cnt FROM feed_reactions WHERE post_id=? GROUP BY emoji
        """, (post_id,))
        rows = await cursor.fetchall()
        return {r[0]: r[1] for r in rows}


# ── Заметки на день/пару ─────────────────────────────────────────────────────

async def add_lesson_note(date_str: str, subject: str, text: str, created_by: int) -> int:
    async with connect() as db:
        cursor = await db.execute("""
            INSERT INTO lesson_notes (date, subject, text, created_by) VALUES (?, ?, ?, ?)
        """, (date_str, subject, text, created_by))
        await db.commit()
        return cursor.lastrowid


async def get_lesson_notes(date_str: str) -> list[dict]:
    async with connect() as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute("""
            SELECT * FROM lesson_notes WHERE date=? ORDER BY created_at
        """, (date_str,))
        return [dict(r) for r in await cursor.fetchall()]


async def delete_lesson_note(note_id: int):
    async with connect() as db:
        await db.execute("DELETE FROM lesson_notes WHERE id=?", (note_id,))
        await db.commit()
