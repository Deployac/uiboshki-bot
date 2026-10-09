"""Капибара везде (владелец, 09.10): про PWA (uiboshki.ru/app) и приложение
рассказываем во всех местах, где бот представляется."""
import bot
from handlers.start import HELP_TEXT, start_text


def test_bot_description_mentions_pwa():
    assert "uiboshki.ru/app" in bot.BOT_DESCRIPTION
    assert "uiboshki.ru" in bot.BOT_SHORT_DESCRIPTION and len(bot.BOT_SHORT_DESCRIPTION) <= 120


def test_start_and_help_mention_pwa():
    assert "uiboshki.ru/app" in start_text("Аня") and "Ещё → Установить" in start_text("Аня")
    assert "uiboshki.ru/app" in HELP_TEXT and "VK" in HELP_TEXT
