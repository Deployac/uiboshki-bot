"""Этап 2 (б): PWA — манифест, service worker, иконки, теги для iPhone."""
import json

from fastapi.testclient import TestClient


def _client():
    import webapp.server as server
    return TestClient(server.app)


def test_manifest_and_icons():
    c = _client()
    r = c.get("/manifest.webmanifest")
    assert r.status_code == 200 and r.headers["content-type"].startswith("application/manifest+json")
    m = json.loads(r.text)
    assert m["start_url"] == "/app" and m["display"] == "standalone"
    for icon in m["icons"]:
        got = c.get(icon["src"])
        assert got.status_code == 200 and got.content[:4] == b"\x89PNG", icon["src"]
    assert any(i.get("purpose") == "maskable" for i in m["icons"])


def test_service_worker_served_for_root_scope():
    r = _client().get("/sw.js")
    assert r.status_code == 200 and r.headers["service-worker-allowed"] == "/"
    assert "no-cache" in r.headers["cache-control"] and "networkFirst" in r.text


def test_index_has_pwa_tags():
    html = _client().get("/app").text
    for tag in ('rel="manifest"', 'rel="apple-touch-icon"', 'apple-mobile-web-app-capable'):
        assert tag in html, tag


def test_sw_syntax():
    import shutil
    import subprocess
    from pathlib import Path
    if not shutil.which("node"):
        return
    sw = Path(__file__).parent.parent / "webapp" / "static" / "sw.js"
    assert subprocess.run(["node", "--check", str(sw)], capture_output=True).returncode == 0
