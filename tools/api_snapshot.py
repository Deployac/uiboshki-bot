"""Снимок API — список «МЕТОД /api/путь» (этап 2: API как контракт).

    python tools/api_snapshot.py        — перезаписать tests/api_contract.json

Тест tests/test_api_contract.py сверяет снимок с живым приложением: пропал
или переименован путь — CI красный (старые версии приложения в магазинах
на него ходят); новый — обнови снимок этой командой, чтобы он попал в
контракт осознанно."""

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SNAPSHOT = ROOT / "tests" / "api_contract.json"


def routes() -> list[str]:
    sys.path.insert(0, str(ROOT))
    os.environ.setdefault("BOT_TOKEN", "123456:SNAPSHOT")
    from webapp.server import app
    out = set()
    for r in app.routes:
        path = getattr(r, "path", "")
        if path.startswith("/api/"):
            for m in sorted(getattr(r, "methods", None) or []):
                if m not in ("HEAD", "OPTIONS"):
                    out.add(f"{m} {path}")
    return sorted(out)


if __name__ == "__main__":
    SNAPSHOT.write_text(json.dumps(routes(), ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"снимок: {SNAPSHOT.relative_to(ROOT)}")
