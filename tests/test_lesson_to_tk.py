"""Нажал на пару на главной → её текущий контроль в СДО: название пары из
расписания сопоставляется с курсом СДО (js/sdo.js: matchCourse)."""
import json
import re
import subprocess
from pathlib import Path

JS = (Path(__file__).parent.parent / "webapp/static/js/sdo.js").read_text()


def _match(title, courses):
    fns = "".join(re.search(r"function %s\(.*?\n}\n" % n, JS, re.S).group(0) for n in ("courseWords", "matchCourse"))
    code = fns + f"const r = matchCourse({json.dumps(title)}, {json.dumps(courses)}); console.log(JSON.stringify(r ? r.id : null));"
    return json.loads(subprocess.run(["node", "-e", code], capture_output=True, text=True, check=True).stdout)


COURSES = [
    {"id": 1, "title": "Анализ и диагностика финансово-хозяйственной деятельности предприятия"},
    {"id": 2, "title": "Основы бизнес-анализа в ИТ-сфере [II.25-26]"},
    {"id": 3, "title": "Моделирование бизнес-процессов"},
    {"id": 4, "title": "Объектно-ориентированный анализ и программирование"},
]


def test_match_course_by_words():
    assert _match("Основы бизнес-анализа в ИТ-сфере", COURSES) == 2       # метка семестра не мешает
    assert _match("Моделирование бизнес-процессов", COURSES) == 3          # не путает с «бизнес-анализом»
    assert _match("Объектно-ориентированный анализ и программирование", COURSES) == 4
    assert _match("Анализ и диагностика финансово-хозяйственной деятельности предприятия", COURSES) == 1
    assert _match("Физическая культура и спорт", COURSES) is None          # нет журнала — не угадываем


def test_own_lessons_tappable_search_not():
    home = (Path(__file__).parent.parent / "webapp/static/js/home.js").read_text()
    search = (Path(__file__).parent.parent / "webapp/static/js/search.js").read_text()
    assert "lessonRow(l, true, true)" in home and "lessonRow(l, !!l.status, true)" in home
    assert "lessonRow(l, !!l.status)" in search    # чужое расписание — без перехода в свой СДО
