"""
Общие middleware диспетчера.

MenuInterruptMiddleware чинит системный баг: нажатие любой кнопки меню
(MENU_BUTTON_TEXTS) во время активного FSM-диалога (добавление дедлайна,
загрузка файла, выбор предмета для решателя и т.д.) раньше могло улететь
как обычный текстовый ввод в базу вместо того, чтобы прервать диалог.
Теперь это проверяется в одном месте для всего бота, а не дублируется
(с расхождениями) в каждом хендлере отдельно.
"""

import logging
from aiogram import BaseMiddleware
from aiogram.types import Message

from keyboards import MENU_BUTTON_TEXTS

logger = logging.getLogger(__name__)


class MenuInterruptMiddleware(BaseMiddleware):
    async def __call__(self, handler, event: Message, data):
        state = data.get("state")
        if state is not None and event.text and event.text in MENU_BUTTON_TEXTS:
            current = await state.get_state()
            if current is not None:
                logger.info(f"Menu button '{event.text}' interrupted FSM state {current} for user {event.from_user.id}")
                # Данные сброшенного диалога отдаём хендлеру кнопки — иначе тот,
                # кому они нужны (solver.stop_dialog чистит сообщения диалога по
                # msg_ids), видит уже пустой state и ничего не может сделать.
                data["interrupted_fsm_data"] = await state.get_data()
                await state.clear()
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
        if user and chat and chat.type == "private":
            import stats
            await stats.track(user.id, "bot")
        return await handler(event, data)
