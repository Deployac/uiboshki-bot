"""Правила кодовых имён (CLAUDE.md): без повторов, придержанные — только где
уже стоят, новые версии — только из песен владельца (tools/changelog.py)."""
import re

import pytest

from tools.changelog import CHANGELOG, RESERVED, SONG_WORDS, check, free, versions

TEXT = CHANGELOG.read_text(encoding="utf-8")


def _key(v):
    return tuple(int(x) for x in v.split("."))


def test_no_duplicate_names_or_versions():
    vs = versions(TEXT)
    names = [n.replace("ё", "е").lower() for _, n in vs]
    assert len(names) == len(set(names))
    assert len({v for v, _ in vs}) == len(vs)


def test_reserved_names_used_only_where_given():
    used = {n for _, n in versions(TEXT)}
    assert used & set(RESERVED) == {"Корнилов", "Кайзер", "Брусилов"}


def test_new_versions_only_from_songs():
    # с v4.21.1 имена сверены с песнями владельца (v4.44.1 «Метель»)
    song = {w.replace("ё", "е").lower() for w in SONG_WORDS}
    temp = set(re.findall(r"^### v([\d.]+) «[^»]+» \(временное имя\)", TEXT, re.M))
    for v, n in versions(TEXT):
        if _key(v) >= (4, 21, 1) and v not in temp:      # временные — владелец заменит
            assert n.replace("ё", "е").lower() in song, f"v{v} «{n}» — не из песен"


def test_tool():
    assert check(TEXT, "Сталин").startswith("придержано")
    assert check(TEXT, "Метель").startswith("занято")
    assert check(TEXT, "Деникин").startswith("нет в песнях")
    from tools.changelog import FIGURES
    assert set(FIGURES) <= set(SONG_WORDS)               # деятели (FIGURES) — тоже разрешены
    assert all(not check(TEXT, n) for n in free(TEXT))
    assert re.search(r"\n## Как будет дальше", TEXT)


def test_temp_name_when_songs_run_out(tmp_path, monkeypatch):
    """Имена кончились — не останавливаться (владелец, 06.10): --temp пускает
    слово не из песен, помечает «(временное имя)», но повтор и придержанные — нет."""
    import tools.changelog as cl
    f = tmp_path / "CHANGELOG.md"
    f.write_text("### v1.0.0 «Метель»\nтекст\n\n## Как будет дальше\n", encoding="utf-8")
    monkeypatch.setattr(cl, "CHANGELOG", f)
    import io
    monkeypatch.setattr(cl.sys, "stdin", io.StringIO("что сделано"))
    assert cl.main(["x", "add", "1.0.1", "Деникин", "--temp"]) == 0
    assert "### v1.0.1 «Деникин» (временное имя)" in f.read_text(encoding="utf-8")
    with pytest.raises(SystemExit):
        cl.main(["x", "add", "1.0.2", "Метель", "--temp"])
    with pytest.raises(SystemExit):
        cl.main(["x", "add", "1.0.2", "Сталин", "--temp"])
