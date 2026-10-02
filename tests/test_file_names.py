"""Понятные названия файлов (/tidyfiles): «ЛК3_бизнес» → «Лекция 3. Бизнес»."""
import pytest

from file_names import tidy_titles, topic_of


def _f(i, title, subject="ООП", file_name="x.pdf", category=None):
    return {"id": i, "title": title, "subject": subject, "file_name": file_name, "category": category}


def test_numbers_types_topics():
    files = [_f(1, "ЛК3 Бизнес-процессы"), _f(2, "Лекция_1_Введение_в_ООП"),
             _f(3, "Тема №2. Классы и объекты", category="lecture"),
             _f(4, "Практическое занятие № 5. Анализ требований"), _f(5, "ПР_4"),
             _f(6, "Лабораторная работа 2"), _f(7, "Методические указания к практике"),
             _f(8, "Вопросы к экзамену.docx"), _f(9, "Тест 1")]
    ch = tidy_titles(files)
    assert ch[1] == "Лекция 3. Бизнес-процессы"
    assert ch[2] == "Лекция 1. Введение в ООП"
    assert ch[3] == "Лекция 2. Классы и объекты"
    assert ch[4] == "Практика 5. Анализ требований"
    assert ch[5] == "Практика 4"
    assert ch[6] == "Лабораторная 2"
    assert 7 not in ch and 9 not in ch                       # и так понятно — не трогаем
    assert ch[8] == "Вопросы к экзамену"                      # не нумеруется, только без «.docx»


def test_no_numbers_numbered_by_upload_order_and_duplicates_marked():
    files = [_f(10, "Презентация к лекции", "Матан", "a.pptx", "lecture"),
             _f(11, "Конспект пределы", "Матан", "c.pdf", "lecture"),
             _f(20, "Лекция 3", "ООП", "l3.pdf"), _f(21, "ЛК 3", "ООП", "l3.pptx")]
    ch = tidy_titles(files)
    assert ch[10] == "Лекция 1" and ch[11] == "Лекция 2. Пределы"
    assert {ch[20], ch[21]} == {"Лекция 3 (PDF)", "Лекция 3 (PPTX)"}


def test_mixed_numbers_unnumbered_not_invented():
    ch = tidy_titles([_f(1, "Лекция 1"), _f(2, "Конспект_пределы", category="lecture")])
    assert ch == {2: "Конспект пределы"}


@pytest.mark.parametrize("t, topic", [("Презентация_тема_2", ""), ("Презентация к лекции", ""),
                                       ("Лекция 3. Бизнес-процессы", "Бизнес-процессы")])
def test_topic(t, topic):
    assert topic_of(t) == topic


@pytest.mark.asyncio
async def test_rename_and_undo(db):
    fid = await db.add_file("ЛК3_бизнес", "ООП", "fid", "lk3.pdf", 1)
    ch = tidy_titles(await db.get_files())
    await db.rename_files(ch)
    await db.rename_files({fid: "Лекция 3. Другое"})            # второй раз — первое название не теряется
    assert (await db.get_files())[0]["title"] == "Лекция 3. Другое"
    assert await db.undo_file_renames() == 1
    assert (await db.get_files())[0]["title"] == "ЛК3_бизнес"
