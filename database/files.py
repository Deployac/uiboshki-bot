"""Файлы курсов, тексты лекций для ИИ и поиск по файлам."""

import aiosqlite

from database._conn import connect


# ── Files ─────────────────────────────────────────────────────────────────────

async def add_file(title, subject, file_id, file_name, uploaded_by, category: str | None = None,
                   source: str | None = None) -> int:
    """category — тип внутри предмета (file_categories); None — определить
    по названию и имени файла. source — откуда файл выгружен автоматически."""
    from file_categories import LABELS, detect_category
    if category not in LABELS:
        category = detect_category(title or "", file_name or "")
    async with connect() as db:
        cursor = await db.execute("""
            INSERT INTO files (title, subject, file_id, file_name, uploaded_by, category, source)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        """, (title, subject, file_id, file_name, uploaded_by, category, source))
        await db.commit()
        return cursor.lastrowid


async def get_file_sources() -> set[str]:
    """Что уже выгружено из СДО — и что удалили вручную (не выгружать снова)."""
    async with connect() as db:
        await db.execute("CREATE TABLE IF NOT EXISTS files_skipped (source TEXT PRIMARY KEY)")
        cursor = await db.execute("SELECT source FROM files WHERE source IS NOT NULL "
                                  "UNION SELECT source FROM files_skipped")
        return {r[0] for r in await cursor.fetchall()}


async def get_file_by_id(fid: int) -> dict | None:
    async with connect() as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute("SELECT * FROM files WHERE id=?", (fid,))
        row = await cursor.fetchone()
        return dict(row) if row else None


async def get_sdo_file_subjects() -> dict[str, tuple[int, str]]:
    """source → (id, предмет) у файлов из СДО: чтобы переложить их, если
    курс раньше сопоставился не с тем предметом."""
    async with connect() as db:
        cursor = await db.execute("SELECT source, id, subject FROM files WHERE source IS NOT NULL")
        return {r[0]: (r[1], r[2] or "") for r in await cursor.fetchall()}


async def set_files_subject(moves: list[tuple[int, str]]):
    """[(id файла, новый предмет)]."""
    async with connect() as db:
        await db.executemany("UPDATE files SET subject=? WHERE id=?", [(s, i) for i, s in moves])
        await db.commit()


async def update_file_meta(fid: int, title: str, subject: str, category: str):
    """Правка файла (WebApp): название, предмет, тип."""
    async with connect() as db:
        await db.execute("UPDATE files SET title=?, subject=?, category=? WHERE id=?", (title, subject, category, fid))
        await db.commit()


async def rename_files(changes: dict[int, str]) -> int:
    """Новые названия (file_names.tidy_titles); старое — в orig_title,
    если его там ещё нет (повторный /tidyfiles не теряет самое первое)."""
    async with connect() as db:
        await db.executemany("UPDATE files SET orig_title = COALESCE(orig_title, title), title = ? WHERE id = ?",
                             [(t, i) for i, t in changes.items()])
        await db.commit()
    return len(changes)


async def undo_file_renames() -> int:
    async with connect() as db:
        cur = await db.execute("UPDATE files SET title = orig_title, orig_title = NULL WHERE orig_title IS NOT NULL")
        await db.commit()
        return cur.rowcount


async def get_files(subject: str = None) -> list[dict]:
    async with connect() as db:
        db.row_factory = aiosqlite.Row
        if subject:
            cursor = await db.execute("SELECT * FROM files WHERE subject=? ORDER BY created_at DESC", (subject,))
        else:
            cursor = await db.execute("SELECT * FROM files ORDER BY created_at DESC")
        return [dict(r) for r in await cursor.fetchall()]


async def delete_file(fid: int):
    await delete_files([fid])


async def delete_files(fids: list[int]) -> int:
    """Удаляет файлы вместе с их текстом для ИИ. Удалённое из СДО
    запоминается (files_skipped), чтобы следующий /sdofiles не выгрузил
    его обратно."""
    if not fids:
        return 0
    marks = ",".join("?" * len(fids))
    async with connect() as db:
        await db.execute("CREATE TABLE IF NOT EXISTS files_skipped (source TEXT PRIMARY KEY)")
        await db.execute(f"INSERT OR IGNORE INTO files_skipped (source) "
                         f"SELECT source FROM files WHERE id IN ({marks}) AND source IS NOT NULL", fids)
        cursor = await db.execute(f"DELETE FROM files WHERE id IN ({marks})", fids)
        deleted = cursor.rowcount
        await db.execute(f"DELETE FROM file_text WHERE file_id IN ({marks})", fids)
        await db.commit()
        return deleted


async def save_file_text(file_id: int, text: str):
    """Сохраняет извлечённый из файла лекции текст (см. file_text.py). Вызывается
    один раз при загрузке/синхронизации файла — не при каждом решении задачи,
    это и есть "кэш" контекста лекций, о котором шла речь в обсуждении."""
    async with connect() as db:
        await db.execute("""
            INSERT INTO file_text (file_id, content, char_count, extracted_at)
            VALUES (?, ?, ?, datetime('now'))
            ON CONFLICT(file_id) DO UPDATE SET
                content=excluded.content, char_count=excluded.char_count, extracted_at=excluded.extracted_at
        """, (file_id, text, len(text)))
        await db.commit()


async def get_subject_lecture_context(subject: str) -> str:
    """Склеенный текст всех лекций предмета (в порядке добавления файлов) —
    контекст для решалки по лекциям (Фаза 9, Gemini). Каждая лекция отделена
    заголовком с названием файла, чтобы при желании модель могла сослаться
    на конкретный источник в ответе."""
    async with connect() as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute("""
            SELECT f.title, ft.content
            FROM file_text ft
            JOIN files f ON f.id = ft.file_id
            WHERE f.subject = ?
            ORDER BY f.id
        """, (subject,))
        rows = await cursor.fetchall()
    return "\n\n".join(f"=== {r['title']} ===\n{r['content']}" for r in rows)


async def get_all_lecture_context() -> str:
    """Тексты лекций всех предметов — для подбора под вопрос в чате без
    выбранного предмета (lecture_picker). Заголовок блока — «предмет: файл»."""
    async with connect() as db:
        db.row_factory = aiosqlite.Row
        cursor = await db.execute("""
            SELECT f.title, f.subject, ft.content
            FROM file_text ft
            JOIN files f ON f.id = ft.file_id
            ORDER BY f.subject, f.id
        """)
        rows = await cursor.fetchall()
    return "\n\n".join(f"=== {r['subject'] or 'Без предмета'}: {r['title']} ===\n{r['content']}" for r in rows)


async def get_file_ids_with_text() -> set[int]:
    """id файлов, текст которых извлечён (участвуют в контексте ИИ) — для
    отметки 📖 в списке файлов WebApp."""
    async with connect() as db:
        cursor = await db.execute("SELECT file_id FROM file_text WHERE char_count > 0")
        return {r[0] for r in await cursor.fetchall()}


async def get_subjects_with_lecture_text() -> list[str]:
    """Предметы, по которым есть хоть один файл с извлечённым текстом — решалка
    по лекциям предлагает выбор только из них (иначе можно было бы выбрать
    предмет без единой лекции и получить пустой контекст)."""
    async with connect() as db:
        cursor = await db.execute("""
            SELECT DISTINCT f.subject FROM file_text ft
            JOIN files f ON f.id = ft.file_id
            WHERE f.subject IS NOT NULL AND f.subject != ''
            ORDER BY f.subject
        """)
        return [r[0] for r in await cursor.fetchall()]


async def search_files(query: str, limit: int = 20) -> list[dict]:
    """Полнотекстовый поиск по title/subject/file_name через FTS5.
    Каждое слово запроса — отдельная кавычка-фраза (без спецсимволов
    FTS5-синтаксиса), между словами — неявный AND. Пустой/бессмысленный
    запрос и отсутствие таблицы (FTS5 недоступен) — просто пустой список,
    а не ошибка."""
    tokens = [t.replace('"', '') for t in query.strip().split() if t.strip('"')]
    if not tokens:
        return []
    fts_query = " ".join(f'"{t}"' for t in tokens)
    try:
        async with connect() as db:
            db.row_factory = aiosqlite.Row
            cursor = await db.execute("""
                SELECT files.* FROM files_fts
                JOIN files ON files.id = files_fts.rowid
                WHERE files_fts MATCH ?
                ORDER BY bm25(files_fts)
                LIMIT ?
            """, (fts_query, limit))
            return [dict(r) for r in await cursor.fetchall()]
    except Exception as e:
        import logging
        logging.getLogger(__name__).warning(f"search_files failed: {e}")
        return []
