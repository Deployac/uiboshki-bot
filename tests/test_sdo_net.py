"""Предохранитель СДО (16.10): СДО не пускает сервер — запросы к нему падают
сразу, а не висят по 30 с, пока приложение пишет «Сервер не отвечает»."""
import httpx
import pytest

import sdo_net


@pytest.fixture(autouse=True)
def _fresh():
    sdo_net.reset()
    yield
    sdo_net.reset()


def _patch(monkeypatch, handler):
    real = httpx.AsyncClient
    calls = []

    def h(req):
        calls.append(req.url.path)
        return handler(req)

    monkeypatch.setattr(httpx, "AsyncClient", lambda *a, **kw: real(*a, transport=httpx.MockTransport(h), **kw))
    return calls


async def test_no_connect_then_fast_fail(monkeypatch):
    def down(req):
        raise httpx.ConnectTimeout("висит", request=req)

    calls = _patch(monkeypatch, down)
    async with sdo_net.client("c") as c:
        with pytest.raises(httpx.ConnectTimeout):
            await c.get("https://online-edu.mirea.ru/my/")
    assert sdo_net.is_down()
    async with sdo_net.client("c") as c:
        with pytest.raises(httpx.ConnectError):          # тот же тип, что ловят обработчики
            await c.get("https://online-edu.mirea.ru/grade/")
    assert calls == ["/my/"]                             # второй раз в сеть не ходили


async def test_works_when_up_and_after_window(monkeypatch):
    calls = _patch(monkeypatch, lambda req: httpx.Response(200, text="ok"))
    sdo_net.mark_down()
    monkeypatch.setattr(sdo_net, "_down_until", 0.0)     # окно прошло — снова пробуем
    async with sdo_net.client("c") as c:
        r = await c.get("https://online-edu.mirea.ru/my/")
    assert r.text == "ok" and calls == ["/my/"]
    assert not sdo_net.is_down()


async def test_http_error_does_not_trip(monkeypatch):
    _patch(monkeypatch, lambda req: httpx.Response(502, text="bad gateway"))
    async with sdo_net.client("c") as c:
        r = await c.get("https://online-edu.mirea.ru/my/")
    assert r.status_code == 502 and not sdo_net.is_down()


def test_connect_timeout_is_short():
    c = sdo_net.client("c", timeout=60)
    assert c.timeout.connect == sdo_net.CONNECT_TIMEOUT and c.timeout.read == 60
