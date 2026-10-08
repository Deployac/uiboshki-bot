"""
Слепое сравнение моделей ИИ на настоящих данных группы (/aitest у старосты).

Зачем: выбрать дешёвую модель для других групп (PLAN.md, «Сколько стоит ИИ»)
не по табличкам, а по ответам на наши вопросы. Берём последние вопросы из
решалки (solver_history) — с теми же кусками лекций, что подобрал бы чат, —
и несколько лекций на конспект; каждую задачу отдаём всем моделям через
OpenRouter (один ключ — OPENROUTER_API_KEY в Railway). Ответы перемешаны и
подписаны «Ответ 1…4»: староста отмечает лучший, не зная модели, и только в
конце открывает, где какая, сколько побед и сколько стоило.

Страница — одна, последняя (settings «aitest:html»), открывается по
подписанной ссылке /aitest?exp=…&sig=… (webapp/routes/aitest.py).
"""

import asyncio
import base64
import json
import logging
import random
import time

import httpx

logger = logging.getLogger(__name__)

URL = "https://openrouter.ai/api/v1/chat/completions"
# кандидаты из PLAN.md: дешёвые (база, проба, конспекты) и подписка
MODELS = {
    "qwen/qwen3.7-flash": "Qwen 3.7 Flash",
    "openai/gpt-oss-120b": "GPT-OSS-120B",
    "google/gemini-2.5-flash-lite": "Gemini 2.5 Flash-Lite",
    "deepseek/deepseek-v4.1-flash": "DeepSeek V4.1 Flash",
}
QUESTIONS = 20
LECTURES = 5
ANSWER_TOKENS = 1500
SUMMARY_TOKENS = 2000
SUMMARY_CHARS = 60_000      # ~15 тыс. токенов — как средняя лекция
PARALLEL = 6
SETTING = "aitest:html"


async def ask(client: httpx.AsyncClient, key: str, model: str, system: str, user: str, max_tokens: int) -> dict:
    """Один ответ модели: текст, цена ($, от OpenRouter), секунды; ошибка — в text."""
    messages = ([{"role": "system", "content": system}] if system else []) + [{"role": "user", "content": user}]
    started = time.monotonic()
    try:
        r = await client.post(URL, headers={"Authorization": f"Bearer {key}"}, json={
            "model": model, "messages": messages, "max_tokens": max_tokens, "usage": {"include": True}})
        data = r.json()
        if r.status_code != 200 or "choices" not in data:
            err = (data.get("error") or {}).get("message") or f"HTTP {r.status_code}"
            return {"text": f"[ошибка: {err}]", "cost": 0.0, "secs": time.monotonic() - started, "error": True}
        text = (data["choices"][0]["message"].get("content") or "").strip()
        return {"text": text or "[пустой ответ]", "cost": float((data.get("usage") or {}).get("cost") or 0),
                "secs": time.monotonic() - started, "error": not text}
    except Exception as e:
        return {"text": f"[ошибка: {type(e).__name__}]", "cost": 0.0, "secs": time.monotonic() - started, "error": True}


def pick_questions(rows: list[tuple[str, str]], n: int = QUESTIONS) -> list[tuple[str, str]]:
    """Разные вопросы, по кругу по предметам: без команд, коротышек и повторов."""
    seen, by_subject = set(), {}
    for text, subject in rows:
        t = (text or "").strip()
        key = " ".join(t.lower().split())
        if len(t) < 15 or len(t) > 800 or t.startswith("/") or key in seen:
            continue
        seen.add(key)
        by_subject.setdefault(subject or "", []).append((t, subject or ""))
    out, queues = [], list(by_subject.values())
    while len(out) < n and any(queues):
        for q in queues:
            if q and len(out) < n:
                out.append(q.pop(0))
    return out


async def _questions() -> list[tuple[str, str]]:
    from database._conn import connect
    async with connect() as db:
        rows = await (await db.execute(
            "SELECT task_text, subject FROM solver_history ORDER BY id DESC LIMIT 500")).fetchall()
    return pick_questions([(r[0], r[1]) for r in rows])


async def _lectures(n: int = LECTURES) -> list[dict]:
    """Лекции с текстом, по одной на предмет — самые свежие."""
    from database._conn import connect
    async with connect() as db:
        rows = await (await db.execute(
            "SELECT f.id, f.title, f.subject, t.content FROM files f JOIN file_text t ON t.file_id = f.id "
            "WHERE t.char_count > 5000 ORDER BY f.id DESC LIMIT 300")).fetchall()
    out, used = [], set()
    for fid, title, subject, content in rows:
        if subject in used:
            continue
        used.add(subject)
        out.append({"id": fid, "title": title, "subject": subject or "", "text": content[:SUMMARY_CHARS]})
        if len(out) == n:
            break
    return out


async def _question_prompt(question: str, subject: str) -> tuple[str, str]:
    """Тот же промпт, что у чата WebApp: куски лекций от поиска по смыслу."""
    import ai_solver
    lectures = ""
    try:
        import semantic_search
        if await semantic_search.ready():
            hits = await semantic_search.search(question, subject)
            if hits:
                lectures, _ = semantic_search.build_context(hits)
    except Exception as e:
        logger.info(f"aitest: поиск для вопроса не сработал: {e}")
    if not lectures:
        return ai_solver.build_system_prompt(subject), question
    user = ai_solver.with_lectures([{"role": "user", "content": question}], lectures)[-1]["content"]
    return ai_solver.lecture_system_prompt(subject, lectures), user


async def run(key: str) -> tuple[str, str]:
    """Прогон: → (страница, короткий итог для старосты)."""
    import gemini_solver
    import lecture_summary
    tasks = []
    for q, subject in await _questions():
        system, user = await _question_prompt(q, subject)
        tasks.append({"kind": "Вопрос", "title": q, "subject": subject, "system": system, "user": user,
                      "tokens": ANSWER_TOKENS})
    for lec in await _lectures():
        tasks.append({"kind": "Конспект", "title": lec["title"], "subject": lec["subject"], "system": "",
                      "user": lecture_summary.PROMPT + "\n\n" + gemini_solver.frame_lectures(lec["text"]),
                      "tokens": SUMMARY_TOKENS})
    if not tasks:
        raise RuntimeError("нет ни вопросов в истории решалки, ни лекций с текстом")
    sem = asyncio.Semaphore(PARALLEL)

    async def one(client, task, model):
        async with sem:
            return await ask(client, key, model, task["system"], task["user"], task["tokens"])

    async with httpx.AsyncClient(timeout=120) as client:
        results = await asyncio.gather(*[one(client, t, m) for t in tasks for m in MODELS])
    items, i = [], 0
    for t in tasks:
        answers = []
        for m in MODELS:
            answers.append(dict(results[i], model=m))
            i += 1
        random.shuffle(answers)
        items.append({"kind": t["kind"], "title": t["title"], "subject": t["subject"], "answers": answers})
    cost = sum(a["cost"] for it in items for a in it["answers"])
    errors = sum(a["error"] for it in items for a in it["answers"])
    summary = (f"Готово: {sum(it['kind'] == 'Вопрос' for it in items)} вопросов и "
               f"{sum(it['kind'] == 'Конспект' for it in items)} конспектов × {len(MODELS)} модели, "
               f"всего ${cost:.3f}" + (f", ошибок {errors}" if errors else ""))
    return page(items), summary


def _answer_html(text: str) -> str:
    from utils import md_to_tg_html_chunks
    return "\n".join(md_to_tg_html_chunks(text)).replace("\n", "<br>")


def page(items: list[dict]) -> str:
    """Страница голосования: ответы без имён моделей; имена, победы и цена —
    по кнопке в конце (выбор хранится в браузере)."""
    from utils import esc
    names = {m: label for m, label in MODELS.items()}
    blocks, key = [], []
    for n, it in enumerate(items):
        answers = "".join(
            f'<div class="a" data-i="{n}" data-j="{j}"><div class="h"><b>Ответ {j + 1}</b>'
            f'<button onclick="vote({n},{j})">Лучший</button></div><div class="t">{_answer_html(a["text"])}</div>'
            f'<div class="m"></div></div>' for j, a in enumerate(it["answers"]))
        blocks.append(f'<section><p class="k">{it["kind"]} {n + 1} · {esc(it["subject"] or "без предмета")}</p>'
                      f'<h2>{esc(it["title"][:400])}</h2>{answers}</section>')
        key.append([[a["model"], round(a["cost"], 6), round(a["secs"], 1)] for a in it["answers"]])
    secret = base64.b64encode(json.dumps({"key": key, "names": names}).encode()).decode()
    return f"""<!doctype html><html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>Слепой тест ИИ</title><style>
body{{margin:0;padding:16px;font:15px/1.5 -apple-system,system-ui,sans-serif;background:#f4f1ea;color:#24221d}}
h1{{font-size:24px;margin:0 0 4px}}.lead{{color:#6c675d;margin:0 0 18px}}
section{{background:#fffdf8;border-radius:18px;padding:14px;margin-bottom:16px;box-shadow:0 1px 0 #e3ddd0}}
.k{{margin:0;color:#b75438;font-size:12px;font-weight:700;text-transform:uppercase}}h2{{font-size:16px;margin:4px 0 10px}}
.a{{border:1.5px solid #e3ddd0;border-radius:14px;padding:10px 12px;margin-top:8px}}.a.on{{border-color:#b75438;background:#fbf1ea}}
.h{{display:flex;justify-content:space-between;align-items:center}}.t{{font-size:14px;margin-top:6px;overflow-wrap:anywhere}}
button{{font:600 13px system-ui;border:0;border-radius:10px;padding:7px 12px;background:#24221d;color:#fff}}
.m{{font-size:12px;color:#b75438;font-weight:700;margin-top:6px}}#res{{white-space:pre-wrap;font:14px/1.6 ui-monospace,monospace}}
.bar{{position:sticky;bottom:0;background:#f4f1ea;padding:10px 0}}
</style></head><body><h1>Слепой тест ИИ</h1><p class="lead">В каждом блоке нажми «Лучший» у самого полезного
ответа. Модели скрыты; выбор сохраняется на этом телефоне. В конце — «Показать модели».</p>
{''.join(blocks)}<div class="bar"><button onclick="reveal()">Показать модели</button> <span id="cnt"></span></div><div id="res"></div>
<script>
const S=JSON.parse(atob("{secret}"));let V={{}};try{{V=JSON.parse(localStorage.getItem("aitest")||"{{}}")}}catch(e){{}}
function paint(){{document.querySelectorAll(".a").forEach(a=>a.classList.toggle("on",V[a.dataset.i]==+a.dataset.j));
document.getElementById("cnt").textContent="выбрано "+Object.keys(V).length+" из {len(items)}"}}
function vote(i,j){{V[i]=j;try{{localStorage.setItem("aitest",JSON.stringify(V))}}catch(e){{}}paint()}}
function reveal(){{const w={{}},c={{}},t={{}};for(const m in S.names){{w[m]=0;c[m]=0;t[m]=0}}
S.key.forEach((row,i)=>row.forEach((a,j)=>{{c[a[0]]+=a[1];t[a[0]]+=a[2];if(V[i]===j)w[a[0]]++}}));
document.querySelectorAll(".a").forEach(a=>{{const r=S.key[a.dataset.i][a.dataset.j];
a.querySelector(".m").textContent=S.names[r[0]]+" · $"+r[1].toFixed(5)+" · "+r[2]+" с"}});
document.getElementById("res").textContent=Object.keys(S.names).sort((x,y)=>w[y]-w[x]).map(m=>
S.names[m]+": побед "+w[m]+", всего $"+c[m].toFixed(4)+", в среднем "+(t[m]/S.key.length).toFixed(1)+" с").join("\\n")}}
paint();
</script></body></html>"""


async def save(html: str) -> None:
    from database import set_setting
    await set_setting(SETTING, html)


async def load() -> str | None:
    from database import get_setting
    return await get_setting(SETTING)
