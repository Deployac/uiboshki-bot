"""Посты канала бота (channel_posts.py, /channel у старосты): загрузка из
папок, выбор формата отправки, превью старосте и публикация по кнопке."""
import time
from types import SimpleNamespace

import pytest
from aiogram import Bot, Dispatcher
from aiogram.client.session.base import BaseSession
from aiogram.fsm.storage.memory import MemoryStorage
from aiogram.types import CallbackQuery, Chat, Message, Update, User

import channel_posts
import config
from tests.conftest import STAROSTA_ID


def _post(root, name, html, images=()):
    d = root / name
    d.mkdir(parents=True)
    (d / "post.html").write_text(html, encoding="utf-8")
    for img in images:
        (d / img).write_bytes(b"\x89PNG fake")
    return d


def test_load_posts_order_title_and_images(tmp_path):
    _post(tmp_path, "02-pause", "<b>Пауза</b>\nтекст", ["10.png", "2.png", "1.jpg"])
    _post(tmp_path, "01-start", "<b>Как всё <i>началось</i></b>\n<blockquote expandable>подробнее</blockquote>")
    (tmp_path / "03-empty").mkdir()                                            # без post.html — не пост
    posts = channel_posts.load_posts(tmp_path)
    assert [p["slug"] for p in posts] == ["01-start", "02-pause"]
    assert posts[0]["title"] == "Как всё началось" and posts[0]["images"] == []
    assert [p.name for p in posts[1]["images"]] == ["1.jpg", "2.png", "10.png"]    # 10 — после 2
    assert channel_posts.visible_len("<b>a&amp;b</b>") == 3
    assert channel_posts.check({"html": "x" * 4097, "images": []}).startswith("текст 4097")


class FakeBot:
    def __init__(self):
        self.calls = []

    async def send_message(self, chat_id, text, **kw):
        self.calls.append(("message", chat_id, text))
        return SimpleNamespace(message_id=len(self.calls))

    async def send_photo(self, chat_id, photo, caption=None, **kw):
        self.calls.append(("photo", chat_id, caption))
        return SimpleNamespace(message_id=len(self.calls))

    async def send_media_group(self, chat_id, media, **kw):
        self.calls.append(("album", chat_id, [m.caption for m in media]))
        return [SimpleNamespace(message_id=len(self.calls) * 10 + i) for i in range(len(media))]


@pytest.mark.asyncio
async def test_send_post_picks_format(tmp_path):
    short, long = "<b>Коротко</b>", "<b>Длинно</b>\n" + "слово " * 300
    one = channel_posts.load_posts(tmp_path) or None
    assert one is None
    _post(tmp_path, "a", short)
    _post(tmp_path, "b", short, ["1.png"])
    _post(tmp_path, "c", short, ["1.png", "2.png"])
    _post(tmp_path, "d", long, ["1.png", "2.png"])
    _post(tmp_path, "e", long, ["1.png"])
    posts = {p["slug"]: p for p in channel_posts.load_posts(tmp_path)}
    bot = FakeBot()
    await channel_posts.send_post(bot, "@ch", posts["a"])
    await channel_posts.send_post(bot, "@ch", posts["b"])
    await channel_posts.send_post(bot, "@ch", posts["c"])
    ids = await channel_posts.send_post(bot, "@ch", posts["d"])
    await channel_posts.send_post(bot, "@ch", posts["e"])
    kinds = [(k, extra) for k, _, extra in bot.calls]
    assert kinds[0] == ("message", short)
    assert kinds[1] == ("photo", short)                                         # короткий — подписью к фото
    assert kinds[2] == ("album", [short, None])                                 # подпись — у первой
    assert kinds[3] == ("album", [None, None]) and kinds[4][0] == "message"     # длинный — альбом, потом текст
    assert len(ids) == 3
    assert kinds[5] == ("photo", None) and kinds[6][0] == "message"


@pytest.mark.asyncio
async def test_published_marks(db):
    assert await channel_posts.published() == {}
    await channel_posts.mark_published("01-start", [5, 6])
    assert (await channel_posts.published())["01-start"]["ids"] == [5, 6]
    assert channel_posts.post_link("@uiboshki_dev", 5) == "https://t.me/uiboshki_dev/5"
    assert channel_posts.post_link("-100123", 5) == ""


def test_channel_id_from_url():
    assert config.channel_id_from("", "https://t.me/uiboshki_dev") == "@uiboshki_dev"
    assert config.channel_id_from("-100777", "https://t.me/uiboshki_dev") == "-100777"
    assert config.channel_id_from("", "https://t.me/+ewZzJ8yHHSFhYWRi") == ""      # приватная ссылка
    assert config.channel_id_from("", "") == ""


class Session(BaseSession):
    def __init__(self):
        super().__init__()
        self.sent = []          # (chat_id, text, кнопки)

    async def close(self):
        pass

    async def make_request(self, bot, method, timeout=None):
        name = type(method).__name__
        if name == "SendMessage":
            kb = method.reply_markup.inline_keyboard if method.reply_markup else []
            self.sent.append((method.chat_id, method.text, [b.callback_data for row in kb for b in row]))
            cid = method.chat_id if isinstance(method.chat_id, int) else -100
            return Message(message_id=len(self.sent), date=0, chat=Chat(id=cid, type="private"), text=method.text).as_(bot)
        if name in ("AnswerCallbackQuery", "EditMessageReplyMarkup"):
            return True
        raise NotImplementedError(name)

    async def stream_content(self, *a, **kw):
        yield b""


@pytest.mark.asyncio
async def test_channel_command_preview_and_publish(db, tmp_path, monkeypatch):
    from handlers import channel
    _post(tmp_path, "01-start", "<b>Как всё началось</b>\nтекст")
    _post(tmp_path, "02-practice", "<b>Проект по программированию</b>")
    monkeypatch.setattr(channel_posts, "POSTS_DIR", tmp_path)
    monkeypatch.setattr(config, "CHANNEL_ID", "@uiboshki_dev")
    bot = Bot(token="123456:TEST-TOKEN-NOT-REAL-AAAAAAAAAAAAAAAAAAA", session=Session())
    dp = Dispatcher(storage=MemoryStorage())
    dp.include_router(channel.router)
    star, other = User(id=STAROSTA_ID, is_bot=False, first_name="S"), User(id=222, is_bot=False, first_name="A")

    async def feed(user, text=None, data=None):
        msg = Message(message_id=1, date=0, chat=Chat(id=user.id, type="private"), from_user=user, text=text or "x")
        upd = (Update(update_id=int(time.time() * 1e6) % 10**9, message=msg) if text else
               Update(update_id=int(time.time() * 1e6) % 10**9,
                      callback_query=CallbackQuery(id="1", from_user=user, chat_instance="c", data=data, message=msg)))
        await dp.feed_update(bot, upd)

    try:
        await feed(other, "/channel")
        assert bot.session.sent[-1][1] == "❌ Только для старосты."
        await feed(other, data="chan:pub:01-start")                              # чужая кнопка — ничего в канал
        assert not any(c == "@uiboshki_dev" for c, _, _ in bot.session.sent)

        await feed(star, "/channel")
        texts = [t for _, t, _ in bot.session.sent]
        assert any("Посты канала" in t and "@uiboshki_dev" in t for t in texts)
        assert texts[-2] == "<b>Как всё началось</b>\nтекст"                      # превью старосте — как в канале
        assert bot.session.sent[-1][2] == ["chan:pub:01-start", "chan:next:01-start"]

        await feed(star, data="chan:pub:01-start")
        assert [c for c, _, _ in bot.session.sent].count("@uiboshki_dev") == 1
        assert "01-start" in await channel_posts.published()
        assert "t.me/uiboshki_dev/" in bot.session.sent[-1][1]
        await feed(star, data="chan:pub:01-start")                               # второй раз — не дублирует
        assert [c for c, _, _ in bot.session.sent].count("@uiboshki_dev") == 1

        await feed(star, "/channel")                                             # следующий — уже второй пост
        assert bot.session.sent[-2][1] == "<b>Проект по программированию</b>"
    finally:
        channel.router._parent_router = None
