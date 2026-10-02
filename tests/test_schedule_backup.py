"""Зеркало расписания МИРЭА лежит → бот отдаёт последний удачный календарь
(из памяти или из базы после перезапуска) и пишет, от какого он времени."""
import httpx
import pytest

import schedule_parser

ICS = b"BEGIN:VCALENDAR\r\nVERSION:2.0\r\nX-WR-CALNAME:test\r\nEND:VCALENDAR\r\n"


class FakeMirror:
    def __init__(self):
        self.mode = "ok"      # ok / down / html

    def client(self, *a, **kw):
        mirror = self

        class C:
            async def __aenter__(self):
                return self

            async def __aexit__(self, *e):
                return False

            async def get(self, url):
                req = httpx.Request("GET", url)
                if mirror.mode == "down":
                    raise httpx.ConnectTimeout("timeout", request=req)
                body = ICS if mirror.mode == "ok" else b"<html>502 Bad Gateway</html>"
                return httpx.Response(200, content=body, request=req)
        return C()


@pytest.fixture
def mirror(monkeypatch):
    m = FakeMirror()
    monkeypatch.setattr(schedule_parser.httpx, "AsyncClient", m.client)
    for name, val in (("_cache_data", None), ("_cache_time", 0.0), ("_ok_at", None), ("_stale", False),
                      ("_backup_hash", None)):
        monkeypatch.setattr(schedule_parser, name, val)
    return m


@pytest.mark.asyncio
async def test_down_mirror_serves_saved_copy(db, mirror):
    assert await schedule_parser.fetch_schedule_raw(force=True) == ICS
    assert schedule_parser.stale_label() is None and schedule_parser.stale_note() == ""

    mirror.mode = "down"                                   # в памяти есть — отдаём её
    assert await schedule_parser.fetch_schedule_raw(force=True) == ICS
    assert schedule_parser.stale_label() and "не отвечает" in schedule_parser.stale_note()

    schedule_parser._cache_data = None                     # «перезапуск»: память пуста — берём из базы
    mirror.mode = "html"                                   # страница ошибки с кодом 200 — тоже не календарь
    assert await schedule_parser.fetch_schedule_raw(force=True) == ICS
    assert schedule_parser.stale_label()

    mirror.mode = "ok"                                     # зеркало ожило — пометка пропала
    assert await schedule_parser.fetch_schedule_raw(force=True) == ICS
    assert schedule_parser.stale_label() is None


@pytest.mark.asyncio
async def test_down_mirror_without_copy_raises(db, mirror):
    mirror.mode = "down"
    with pytest.raises(httpx.HTTPError):
        await schedule_parser.fetch_schedule_raw(force=True)
