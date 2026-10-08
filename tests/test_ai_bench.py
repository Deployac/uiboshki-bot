"""Слепой тест моделей ИИ (ai_bench.py, /aitest): выбор вопросов, страница
без имён моделей, прогон и подписанная ссылка на страницу."""
import base64
import json
import re

import pytest
from fastapi.testclient import TestClient

import ai_bench


def test_pick_questions_skips_junk_and_rotates_subjects():
    rows = [("/start", "А"), ("коротко", "А"), ("Как считать NPV проекта?", "Финансы"),
            ("как считать  npv проекта?", "Финансы"),                       # повтор
            ("Что такое нормализация БД?", "Базы"), ("Объясни ROI по лекции", "Финансы")]
    got = ai_bench.pick_questions(rows, 3)
    assert [s for _, s in got] == ["Финансы", "Базы", "Финансы"]           # по кругу по предметам
    assert all(not q.startswith("/") and len(q) >= 15 for q, _ in got)


def test_page_hides_models_until_reveal():
    items = [{"kind": "Вопрос", "title": "Что такое NPV?", "subject": "Финансы", "answers": [
        {"model": m, "text": f"**ответ** {i}", "cost": 0.0001, "secs": 1.2, "error": False}
        for i, m in enumerate(ai_bench.MODELS)]}]
    html = ai_bench.page(items)
    visible = re.sub(r'atob\("[^"]+"\)', "", html)
    assert not any(label in visible for label in ai_bench.MODELS.values())  # имён моделей не видно
    assert "Ответ 4" in html and "<b>ответ</b>" in html
    secret = json.loads(base64.b64decode(re.search(r'atob\("([^"]+)"\)', html).group(1)))
    assert [a[0] for a in secret["key"][0]] == list(ai_bench.MODELS)       # ключ — для «Показать модели»


@pytest.mark.asyncio
async def test_run_on_group_data(db, monkeypatch):
    from database._conn import connect
    async with connect() as c:
        await c.execute("INSERT INTO solver_history (user_id, task_text, answer, subject) VALUES "
                        "(1, 'Как считать NPV инвестиционного проекта?', 'x', 'Финансы')")
        await c.commit()
    fid = await db.add_file("Лекция 1", "Финансы", "tg", "l1.pdf", 1)
    await db.save_file_text(fid, "Дисконтирование денежных потоков. " * 400)
    calls = []

    async def fake_ask(client, key, model, system, user, max_tokens):
        calls.append((model, user[:20]))
        return {"text": f"ответ {model}", "cost": 0.001, "secs": 0.5, "error": False}

    monkeypatch.setattr(ai_bench, "ask", fake_ask)
    html, summary = await ai_bench.run("k")
    assert len(calls) == 2 * len(ai_bench.MODELS)                            # вопрос и конспект — всем моделям
    assert "1 вопросов и 1 конспектов" in summary and "$0.008" in summary
    await ai_bench.save(html)
    assert await ai_bench.load() == html


@pytest.mark.asyncio
async def test_page_link_is_signed(db, monkeypatch):
    import webapp.server as server
    from webapp import deps
    from webapp.routes import aitest
    monkeypatch.setattr(deps, "BOT_TOKEN", "123:abc")
    monkeypatch.setattr(deps, "WEBAPP_URL", "https://www.uiboshki.ru")
    path = aitest.link().split("uiboshki.ru")[1]
    assert path.startswith("/aitest?exp=")
    c = TestClient(server.app)
    assert c.get(path).status_code == 404                                     # страницы ещё нет
    await ai_bench.save("<p>тест</p>")
    r = c.get(path)
    assert r.status_code == 200 and "тест" in r.text and r.headers["cache-control"] == "no-store"
    assert c.get(path.replace("sig=", "sig=0")).status_code == 404            # чужая подпись
    assert c.get("/aitest").status_code == 404
