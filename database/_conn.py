"""Подключение к базе. Путь читается в момент вызова (database.DATABASE_PATH),
а не копируется при импорте: тесты и /restore подменяют его в одном месте."""

import aiosqlite

import database


def connect():
    return aiosqlite.connect(database.DATABASE_PATH)
