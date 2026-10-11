"""152-ФЗ, пока бот на Railway: согласие, «удалить все мои данные», срок
хранения. Тексты — legal_texts.py (страницы /consent и /privacy, JSON
/api/legal/<имя> — webapp/routes/legal.py).

Согласие (ст. 9) — отдельной галочкой, по умолчанию не стоит: общее (`pd`) —
при первом входе (бот — кнопка «Даю согласие», PWA и приложение — лист), на
вход в СДО (`sdo`) — своя галочка у поля куки, без неё сервер куку не берёт.
Поменял текст согласия по смыслу — подними VERSION: всех спросят заново.

Срок хранения: год без заходов — всё стирается той же erase_user; запросы
решалки — полгода."""

import logging

from config import STAROSTA_IDS

logger = logging.getLogger(__name__)

VERSION = "1"
DATE = "11.10.2026"
KINDS = ("pd", "sdo")
VIAS = ("bot", "pwa", "tg", "app")

INACTIVE_DAYS = 365
SOLVER_DAYS = 180
BACKUP_DAYS = 30               # копии базы у оператора — не дольше (политика)

# Кто оператор и как связаться — в текстах согласия и политики (legal_texts.py)
OPERATOR = "Никита, разработчик сервиса «Капибара» (самозанятый)"
CONTACT = "Telegram @Partykq"
CONTACT_URL = "https://t.me/Partykq"

_seen: dict[int, str] = {}     # id → день последней отметки (пишем раз в день)


async def needs(user_id: int, kind: str = "pd") -> bool:
    from database.privacy import has_consent
    return not await has_consent(user_id, kind, VERSION)


async def give(user_id: int, kind: str, via: str):
    from database.privacy import give_consent
    if kind not in KINDS:
        raise ValueError(kind)
    await give_consent(user_id, kind, VERSION, via if via in VIAS else "pwa")


async def seen(user_id: int):
    """Отметить заход (для срока хранения) — не чаще раза в день."""
    from datetime import date
    today = date.today().isoformat()
    if _seen.get(user_id) == today:
        return
    _seen[user_id] = today
    try:
        from database.privacy import touch_seen
        await touch_seen(user_id)
    except Exception as e:
        logger.info(f"last_seen: {e}")


async def erase(user_id: int) -> dict:
    """Всё о человеке — из базы и кэшей. Копии базы (бэкапы) уходят сами,
    когда сменяются (политика это говорит)."""
    from database.privacy import erase_user
    done = await erase_user(user_id, STAROSTA_IDS)
    _seen.pop(user_id, None)
    try:
        import sdo_grades
        sdo_grades.forget(user_id)
    except Exception:
        pass
    logger.info(f"удалены данные человека: {sum(done.values())} строк")
    return done


async def purge():
    """Раз в сутки (scheduler): год без заходов — стереть; старые запросы решалки."""
    from database.privacy import inactive_users, purge_solver_history
    gone = [u for u in await inactive_users(INACTIVE_DAYS) if u not in STAROSTA_IDS]
    for uid in gone:
        await erase(uid)
    n = await purge_solver_history(SOLVER_DAYS)
    if gone or n:
        logger.info(f"срок хранения: людей {len(gone)}, запросов решалки {n}")
