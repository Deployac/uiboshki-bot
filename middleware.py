"""
Общие middleware диспетчера.

MenuInterruptMiddleware чинит системный баг: нажатие любой кнопки меню
(MENU_BUTTON_TEXTS) во время активного FSM-диалога (добавление дедлайна,
загрузка файла, выбор предмета для решателя и т.д.) раньше могло улететь
как обычный текстовый ввод в базу вместо того, чтобы прервать диалог.
Теперь это проверяется в одном месте для всего бота, а не дублируется
(с расхождениями) в каждом хендлере отдельно. То же — любая команда («/help»
посреди /feed раньше оставляла состояние, и следующий текст уходил в группу
анонимно; «/stats» посреди /announce рассылался всей группе).
"""

import logging
import re

from aiogram import BaseMiddleware
from aiogram.types import Message

from keyboards import MENU_BUTTON_TEXTS

logger = logging.getLogger(__name__)

_COMMAND = re.compile(r"^/[A-Za-z0-9_]")

# Анонимные сценарии: ни сами команды, ни ввод в их состояниях не пишутся в
# статистику — иначе по времени события в «Кто пользуется» видно автора поста.
ANON_TEXTS = {"🗣 Подслушано", "❓ Вопрос анон"}
ANON_COMMANDS = {"feed", "anon"}
ANON_STATES = {"FeedPost:waiting", "AnonQuestion:waiting"}


def is_command(text: str | None) -> bool:
    return bool(text and _COMMAND.match(text))


def _command_name(text: str | None) -> str:
    if not is_command(text):
        return ""
    return text[1:].split(maxsplit=1)[0].split("@", 1)[0].lower()


def is_anonymous(text: str | None, raw_state: str | None) -> bool:
    return raw_state in ANON_STATES or text in ANON_TEXTS or _command_name(text) in ANON_COMMANDS


class MenuInterruptMiddleware(BaseMiddleware):
    async def __call__(self, handler, event: Message, data):
        state = data.get("state")
        text = event.text
        if state is not None and text and (text in MENU_BUTTON_TEXTS or is_command(text)):
            current = await state.get_state()
            if current is not None:
                # Без id человека: в логе не должно быть видно, кто сидел в /feed.
                logger.info(f"'{text[:32]}' interrupted FSM state {current}")
                # Данные сброшенного диалога отдаём хендлеру кнопки — иначе тот,
                # кому они нужны (solver.stop_dialog чистит сообщения диалога по
                # msg_ids), видит уже пустой state и ничего не может сделать.
                data["interrupted_fsm_data"] = await state.get_data()
                data["interrupted_fsm_state"] = current
                await state.clear()
                # Фильтры состояний смотрят на raw_state, посчитанный aiogram
                # ДО этого middleware: без сброса хендлеры старого состояния
                # (send_announce, publish_feed_post) всё равно ловили бы апдейт.
                data["raw_state"] = None
        return await handler(event, data)


class OptionalSubjectsMiddleware(BaseMiddleware):
    """Скрывает пары предметов по выбору, на которые человек не ходит
    (optional_subjects.HIDE), для всего, что бот делает по его апдейту."""
    async def __call__(self, handler, event, data):
        user = data.get("event_from_user")
        if user:
            from optional_subjects import apply_for
            try:
                await apply_for(user.id)
            except Exception as e:
                logger.warning(f"optional subjects: {e}")
        return await handler(event, data)


class StatsMiddleware(BaseMiddleware):
    """Сообщение боту в личку — событие «чат с ботом» для /stats (stats.py)."""
    async def __call__(self, handler, event, data):
        user = getattr(event, "from_user", None)
        chat = getattr(event, "chat", None)
        if user and chat and chat.type == "private" \
                and not is_anonymous(getattr(event, "text", None), data.get("raw_state")):
            import stats
            await stats.track(user.id, "bot")
        return await handler(event, data)
