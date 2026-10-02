"""
Понятные названия файлов внутри предмета (просьба владельца: «чтобы было
понятно — Лекция 1, Лекция 2, Лекция 3…»). Из СДО файлы приходят с какими
угодно названиями: «Презентация_тема_2», «ЛК3 Бизнес-процессы.pdf»,
«Практическое занятие №5. Анализ», «Тема 1. Введение».

tidy_titles(files) → {id: новое название}: тип (file_categories) + номер +
тема, если она есть: «Лекция 3. Бизнес-процессы», «Практика 5. Анализ».
Номер берётся из названия; если ни у одного файла этого типа в предмете
номера нет — нумеруем по порядку выгрузки (он идёт по курсу в СДО).
Методички, экзаменационное и «другое» не нумеруются — только чистится
мусор (подчёркивания, расширение). Применяет староста командой /tidyfiles
(сначала показывает, что поменяется); старое название хранится в
files.orig_title — «/tidyfiles undo» возвращает всё как было.
"""

import re

from file_categories import category_of, natural_key

NUMBERED = ("lecture", "practice", "control")

_KEY = (r"лекци[а-яё]*|лк|тем[аы]?|практ[а-яё]*|пр|лаб[а-яё]*|лр|семинар[а-яё]*|занят[а-яё]*|работ[а-яё]*|кр|"
        r"контрольн[а-яё]*|тест[а-яё]*|задани[а-яё]*|модул[а-яё]*|раздел[а-яё]*|часть|ч\.")
# «Лекция 3», «ЛК3», «Тема №2», «ПР_4», «Практическое занятие № 5», «Практика11 12» (11–12),
# «Практическая работа 5 6» / «5-6» / «5 и 6» — две практики в одном файле
_RANGE = r"(\d{1,2})(?:\s*(?:[-–—,]|и)\s*|\s+)(\d{1,2})(?![\da-z])"
_NUM = re.compile(r"(?<![а-яёa-z])(?:" + _KEY + r")(?:\s+[а-яё]+)?\s*[№#]?\s*(?:" + _RANGE + r"|(\d{1,2})(?!\d))", re.I)
_EXT = re.compile(r"\.(pdf|docx?|pptx?|xlsx?|odt|odp|rtf|txt|zip|rar|7z|png|jpe?g)$", re.I)
_PREFIX = re.compile(r"^\s*(?:" + _KEY + r")(?:\s+[а-яё]+)?\s*[№#]?\s*(?:" + _RANGE + r"|\d{1,2}(?!\d))\s*[.:)\-–—]*\s*", re.I)
_GENERIC = re.compile(r"^(?:презентац\w*|материал\w*|файл|слайды|конспект|лекци\w*|практ\w*|"
                      r"задани\w*|к\s+лекции|к\s+практике)$", re.I)


def clean(title: str) -> str:
    """Подчёркивания → пробелы, без расширения и лишних пробелов/знаков по краям."""
    t = _EXT.sub("", (title or "").strip())
    t = re.sub(r"[_]+", " ", t)
    t = re.sub(r"\s+", " ", t).strip(" .-–—:")
    return t[:1].upper() + t[1:] if t else t


def number_of(title: str) -> str | None:
    """Номер из названия: «3», а для двух подряд — «5–6» («Практика 5 6»)."""
    m = _NUM.search((title or "").replace("_", " "))
    if not m:
        return None
    a, b, one = m.group(1), m.group(2), m.group(3)
    if one:
        return str(int(one))
    if int(b) == int(a) + 1:
        return f"{int(a)}–{int(b)}"
    return str(int(a))           # «Практика 1 Знакомство 7» сюда не попадёт, а «Тема 2 3D» — номер 2


def word_for(cat: str, title: str) -> str:
    low = (title or "").lower()
    if cat == "lecture":
        return "Лекция"
    if cat == "practice":
        return "Лабораторная" if re.search(r"лаб|(?<![а-яё])лр(?![а-яё])", low) else "Практика"
    return "Тест" if "тест" in low else "Контрольная"


def topic_of(title: str) -> str:
    """Тема без «Лекция 3.» в начале; пусто, если там только общее слово."""
    t = clean(title)
    for _ in range(2):      # «Презентация_тема_2»: сначала служебное слово, потом «тема 2»
        t = _PREFIX.sub("", t, count=1).strip(" .-–—:")
        t = re.sub(r"^(?:тема|по теме)\s*[:.]?\s*", "", t, flags=re.I).strip(" .-–—:")
        # «Презентация к лекции», «Конспект пределы» → без служебного слова
        t = re.sub(r"^(?:презентац\w*|конспект\w*|слайды|материал\w*)(?:\s+(?:к|по|для)\s+(?:лекци\w*|практ\w*|"
                   r"занят\w*|тем\w*))?\s*[.:\-–—]*\s*", "", t, flags=re.I).strip(" .-–—:")
    if not t or _GENERIC.match(t) or t.isdigit():
        return ""
    t = t[:1].upper() + t[1:]
    return t if len(t) <= 70 else t[:67].rstrip() + "…"


def tidy_titles(files: list[dict]) -> dict[int, str]:
    """{id: новое название} для файлов, у которых название меняется.
    files — все файлы (dict из базы: id, title, subject, category, file_name)."""
    groups: dict[tuple, list[dict]] = {}
    for f in files:
        groups.setdefault((f.get("subject") or "", category_of(f)), []).append(f)
    out: dict[int, str] = {}
    for (_, cat), items in groups.items():
        if cat not in NUMBERED:
            for f in items:
                new = clean(f["title"])
                if new and new != f["title"]:
                    out[f["id"]] = new
            continue
        numbered = {f["id"]: number_of(f["title"]) or number_of(f.get("file_name") or "") for f in items}
        if not any(numbered.values()):
            # номеров нет ни у кого — по порядку выгрузки (id растёт по курсу СДО)
            for i, f in enumerate(sorted(items, key=lambda f: f["id"]), 1):
                numbered[f["id"]] = str(i)
        for f in items:
            n = numbered[f["id"]]
            if not n:
                new = clean(f["title"])          # у соседей номера есть, а у него нет — не выдумываем
            else:
                topic = topic_of(f["title"])
                new = f"{word_for(cat, f['title'] + ' ' + (f.get('file_name') or ''))} {n}" + (f". {topic}" if topic else "")
            if new and new != f["title"]:
                out[f["id"]] = new
    # одинаковые названия в одном предмете (PDF и презентация одной лекции) — с типом файла
    by_name: dict[tuple, list[int]] = {}
    for f in files:
        by_name.setdefault((f.get("subject") or "", out.get(f["id"], f["title"])), []).append(f["id"])
    ext = {f["id"]: (_EXT.search(f.get("file_name") or "") or [None, ""])[1].lower() for f in files}
    for (_, name), ids in by_name.items():
        if len(ids) > 1:
            for fid in ids:
                if ext[fid]:
                    out[fid] = f"{name} ({ext[fid].upper()})"
    return out


def preview(files: list[dict], changes: dict[int, str], limit: int = 25) -> list[str]:
    """Строки «было → стало» по предметам, для сообщения старосте."""
    from utils import esc
    by_id = {f["id"]: f for f in files}
    rows = sorted(changes.items(), key=lambda kv: (by_id[kv[0]].get("subject") or "", natural_key(kv[1])))
    lines, last = [], None
    for fid, new in rows[:limit]:
        subj = by_id[fid].get("subject") or "Без предмета"
        if subj != last:
            lines.append(f"\n<b>{esc(subj)}</b>")
            last = subj
        lines.append(f"• {esc(by_id[fid]['title'])} → <b>{esc(new)}</b>")
    return lines


def full_list(files: list[dict], changes: dict[int, str]) -> str:
    """Все переименования текстом для файла: по предметам, «было → стало»."""
    by_id = {f["id"]: f for f in files}
    rows = sorted(changes.items(), key=lambda kv: (by_id[kv[0]].get("subject") or "", natural_key(kv[1])))
    out, last = [], None
    for fid, new in rows:
        subj = by_id[fid].get("subject") or "Без предмета"
        if subj != last:
            out.append(("\n" if out else "") + f"== {subj} ==")
            last = subj
        out.append(f"{by_id[fid]['title']}  →  {new}")
    return "\n".join(out) + "\n"
