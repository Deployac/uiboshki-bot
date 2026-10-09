"""Имя iOS-приложения: в Info.plist — латиницей, «Капибара» — из InfoPlist.strings.

AltServer с бесплатным Apple ID регистрирует App ID по CFBundleDisplayName
из Info.plist, и Apple отвечает «The name for this app is invalid» на
кириллицу (09.10, установка IPA на iPhone владельца)."""
import plistlib
from pathlib import Path

RUNNER = Path(__file__).resolve().parent.parent / "app" / "ios" / "Runner"
PBXPROJ = RUNNER.parent / "Runner.xcodeproj" / "project.pbxproj"


def test_display_name_in_plist_is_ascii():
    info = plistlib.loads((RUNNER / "Info.plist").read_bytes())
    for key in ("CFBundleDisplayName", "CFBundleName"):
        assert info[key].isascii(), key


def test_localized_name_is_kapibara_and_bundled():
    for lang in ("en", "ru"):
        text = (RUNNER / f"{lang}.lproj" / "InfoPlist.strings").read_text(encoding="utf-8")
        assert '"CFBundleDisplayName" = "Капибара";' in text
        assert f"path = {lang}.lproj/InfoPlist.strings;" in PBXPROJ.read_text(encoding="utf-8")
    assert "InfoPlist.strings in Resources */," in PBXPROJ.read_text(encoding="utf-8")
