"""
Вход в СДО у каждого студента свой: кука MoodleSession, которую человек
сам вставляет в WebApp (меню «Ещё» → СДО). Нужна, чтобы сдавать работы
из WebApp от своего имени (sdo_submit.py).

Кука в базе только зашифрованной (Fernet). Ключ — переменная SDO_CRYPT_KEY,
а если её нет — производный от BOT_TOKEN: утечка одной базы (бэкап в чате
старосты) не раскрывает чужие входы. В логи и ответы значение не попадает.

Раз в 55 минут (scheduler.py) куки проверяются и заодно держат сессию живой;
разлогиненная помечается expired, и человеку один раз приходит сообщение.
"""

import base64
import hashlib
import logging
import os
import re

import httpx
from cryptography.fernet import Fernet, InvalidToken, MultiFernet

from config import BOT_TOKEN, SDO_BASE_URL, SDO_SESSION_COOKIE, STAROSTA_ID, is_starosta

logger = logging.getLogger(__name__)

COOKIE_RE = re.compile(r"^[A-Za-z0-9,\-]{16,128}$")


def _bot_token_key() -> bytes:
    digest = hashlib.sha256(b"uiboshki-sdo-cookie:" + (BOT_TOKEN or "").encode()).digest()
    return base64.urlsafe_b64encode(digest)


def _passphrase_key(phrase: str) -> bytes:
    """Ключ из секретной фразы владельца (SDO_CRYPT_PASSPHRASE в Railway):
    scrypt — медленная функция, перебором фразу не подобрать. Соль своя для
    бота: одна и та же фраза в другом проекте даст другой ключ."""
    raw = hashlib.scrypt(phrase.encode(), salt=b"uiboshki-bot/sdo-cookies/v1", n=2 ** 14, r=8, p=1, dklen=32)
    return base64.urlsafe_b64encode(raw)


def _keys() -> list[bytes]:
    """Ключи по старшинству: первым шифруем, любым — расшифровываем. Так
    можно сменить ключ (задать фразу) без потери уже подключённых СДО —
    старые записи перешифровываются при проверке входа (keepalive_all)."""
    keys = []
    if os.getenv("SDO_CRYPT_KEY"):
        keys.append(os.getenv("SDO_CRYPT_KEY").encode())
    if os.getenv("SDO_CRYPT_PASSPHRASE"):
        keys.append(_passphrase_key(os.getenv("SDO_CRYPT_PASSPHRASE")))
    keys.append(_bot_token_key())
    return keys


def _fernet() -> MultiFernet:
    return MultiFernet([Fernet(k) for k in _keys()])


def key_source() -> str:
    """Откуда ключ — для экрана «Безопасность» (без самого ключа)."""
    if os.getenv("SDO_CRYPT_KEY"):
        return "key"
    if os.getenv("SDO_CRYPT_PASSPHRASE"):
        return "passphrase"
    return "bot_token"


def needs_rotation(token: str) -> bool:
    """Запись зашифрована не основным ключом — перешифровать."""
    try:
        Fernet(_keys()[0]).decrypt(token.encode())
        return False
    except (InvalidToken, ValueError):
        return True


def encrypt(cookie: str) -> str:
    return _fernet().encrypt(cookie.encode()).decode()


def decrypt(token: str) -> str | None:
    try:
        return _fernet().decrypt(token.encode()).decode()
    except (InvalidToken, ValueError):
        return None


def clean_cookie(raw: str) -> str | None:
    """Значение из поля ввода: «MoodleSession=abc», «abc;», с пробелами —
    всё сводим к самому значению. None — не похоже на куку."""
    value = (raw or "").strip().strip(";").strip()
    if "=" in value:
        value = value.split("=", 1)[1].strip()
    value = value.strip('"').strip()
    return value if COOKIE_RE.match(value) else None


def client_for(cookie: str, **kwargs) -> httpx.AsyncClient:
    return httpx.AsyncClient(cookies={"MoodleSession": cookie}, follow_redirects=True,
                             timeout=kwargs.pop("timeout", 30), **kwargs)


async def check(cookie: str) -> bool:
    """True — кука рабочая (СДО пускает на /my/). Сетевая ошибка —
    исключение: «СДО не отвечает» не значит «вход устарел»."""
    from sdo_parser import SdoSessionExpired, get_checked
    async with client_for(cookie) as client:
        try:
            await get_checked(client, f"{SDO_BASE_URL}/my/")
        except SdoSessionExpired:
            return False
    return True


async def cookie_for(user_id: int) -> str | None:
    """Рабочая кука человека. У старосты, если он свою не подключал, —
    общая из Railway (SDO_SESSION_COOKIE): это и есть его вход."""
    from database import get_sdo_session
    row = await get_sdo_session(user_id)
    if row and row["status"] == "ok":
        return decrypt(row["cookie_enc"])
    if not row and is_starosta(user_id) and SDO_SESSION_COOKIE:
        return SDO_SESSION_COOKIE
    return None


async def status_for(user_id: int) -> dict:
    from database import get_sdo_session
    row = await get_sdo_session(user_id)
    if row:
        return {"state": "ok" if row["status"] == "ok" else "expired", "checked_at": row["checked_at"]}
    if is_starosta(user_id) and SDO_SESSION_COOKIE:
        return {"state": "ok", "checked_at": None, "shared": True}
    return {"state": "off"}


async def keepalive_all(bot=None):
    """Проверить все подключённые входы. Разлогиненный — expired и одно
    сообщение человеку; сеть упала — ничего не трогаем."""
    from database import get_sdo_sessions, set_sdo_status
    for row in await get_sdo_sessions("ok"):
        cookie = decrypt(row["cookie_enc"])
        if cookie and needs_rotation(row["cookie_enc"]):
            from database import save_sdo_session
            await save_sdo_session(row["user_id"], encrypt(cookie))   # на новый ключ
        try:
            alive = bool(cookie) and await check(cookie)
        except Exception as e:
            logger.info(f"СДО keepalive {row['user_id']}: {type(e).__name__}")
            continue
        await set_sdo_status(row["user_id"], "ok" if alive else "expired")
        if not alive and bot:
            try:
                from keyboards import app_button
                await bot.send_message(row["user_id"],
                    "🎓 Вход в СДО устарел — баллы и сдача работ в приложении пока не работают.\n"
                    "Подключи заново: приложение → СДО → Вход.",
                    reply_markup=app_button("🎓 Подключить СДО", "sdo"))
            except Exception:
                pass
