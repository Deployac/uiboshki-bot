"""
Резервная копия базы: раз в сутки (и по /backup) бот присылает старосте
сжатую копию SQLite — все файлы, дедлайны, заметки, закреплённые. Раньше
всё жило в одном файле на Railway без копий: потеря тома — потеря всего.

Копия снимается штатным sqlite3 backup API — консистентно, даже если бот
в этот момент пишет в базу.

Восстановить — /restore у старосты: прислать боту файл копии (.db.gz или
.db), бот проверяет целостность и таблицы, показывает, что внутри, и после
подтверждения сначала присылает копию текущей базы, потом переливает копию
на её место тем же backup API (без перезапуска) и докатывает миграции.
"""

import asyncio
import gzip
import logging
import os
import sqlite3
import tempfile
import zlib
from datetime import datetime

import database
import health
from utils import TZ

logger = logging.getLogger(__name__)

MAX_SEND_BYTES = 48 * 1024 * 1024   # sendDocument бота — до 50 МБ


def _snapshot(db_path: str) -> bytes:
    fd, tmp = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    try:
        src = sqlite3.connect(db_path)
        dst = sqlite3.connect(tmp)
        try:
            src.backup(dst)
        finally:
            dst.close()
            src.close()
        with open(tmp, "rb") as f:
            return gzip.compress(f.read(), compresslevel=6)
    finally:
        os.remove(tmp)


async def make_backup() -> tuple[bytes, str]:
    data = await asyncio.to_thread(_snapshot, database.DATABASE_PATH)
    return data, f"uiboshki-{datetime.now(TZ).strftime('%Y-%m-%d_%H-%M')}.db.gz"


async def send_backup(bot, chat_id: int, silent: bool = True) -> bool:
    from aiogram.types import BufferedInputFile
    try:
        data, name = await make_backup()
    except Exception as e:
        logger.error(f"backup: не снялась копия базы: {e}")
        await health.note("backup", False, "копия не снялась")
        await bot.send_message(chat_id, f"⚠️ Не получилось снять копию базы: {e}")
        return False
    size_mb = len(data) / 1024 / 1024
    if len(data) > MAX_SEND_BYTES:
        await health.note("backup", False, f"{size_mb:.0f} МБ — больше лимита Telegram")
        await bot.send_message(chat_id, f"⚠️ Копия базы — {size_mb:.0f} МБ, больше лимита Telegram (50 МБ).")
        return False
    await bot.send_document(
        chat_id, BufferedInputFile(data, filename=name), disable_notification=silent,
        caption=(f"💾 Копия базы ({size_mb:.1f} МБ). Храни — это все файлы, дедлайны и заметки.\n"
                 "Восстановить: распаковать .gz и положить вместо базы на томе Railway."),
    )
    await health.note("backup", True, f"{size_mb:.1f} МБ")
    return True


# ── Восстановление (/restore) ───────────────────────────────────────────────

REQUIRED_TABLES = ("users", "deadlines", "files")
MAX_RESTORE_BYTES = 20 * 1024 * 1024    # скачать файл бот может до 20 МБ (Bot API)


class RestoreError(ValueError):
    """Копия не подходит — текст для старосты."""


def inspect_backup(raw: bytes) -> tuple[str, dict]:
    """Проверить присланную копию: распаковать, integrity_check, нужные
    таблицы. Возвращает (путь к временному .db, сводка). Временный файл
    удаляет apply_backup или вызывающий."""
    if raw[:2] == b"\x1f\x8b":
        try:
            raw = gzip.decompress(raw)
        except (OSError, EOFError, zlib.error):
            raise RestoreError("архив повреждён — не распаковался")
    if not raw.startswith(b"SQLite format 3\x00"):
        raise RestoreError("это не база SQLite (нужен файл uiboshki-….db.gz из /backup)")
    fd, tmp = tempfile.mkstemp(suffix=".db")
    with os.fdopen(fd, "wb") as f:
        f.write(raw)
    try:
        con = sqlite3.connect(tmp)
        try:
            ok = con.execute("PRAGMA integrity_check").fetchone()[0]
            if ok != "ok":
                raise RestoreError(f"база повреждена: {ok}")
            tables = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            missing = [t for t in REQUIRED_TABLES if t not in tables]
            if missing:
                raise RestoreError("в копии нет таблиц: " + ", ".join(missing))
            count = lambda t: con.execute(f"SELECT COUNT(*) FROM {t}").fetchone()[0] if t in tables else 0  # noqa: E731
            summary = {"users": count("users"), "deadlines": count("deadlines"), "files": count("files"),
                       "sdo": count("sdo_sessions"), "size_mb": round(len(raw) / 1024 / 1024, 1)}
        finally:
            con.close()
    except Exception:
        os.remove(tmp)
        raise
    return tmp, summary


def _copy_into(src_path: str, dst_path: str):
    src = sqlite3.connect(src_path)
    dst = sqlite3.connect(dst_path)
    try:
        src.backup(dst)          # целиком заменяет содержимое dst, атомарно для читателей
    finally:
        dst.close()
        src.close()


async def apply_backup(tmp_path: str):
    """Перелить проверенную копию на место текущей базы и докатить миграции
    (копия могла быть снята старой версией бота)."""
    try:
        await asyncio.to_thread(_copy_into, tmp_path, database.DATABASE_PATH)
    finally:
        if os.path.exists(tmp_path):
            os.remove(tmp_path)
    await database.init_db()
