"""Безопасность: ключ из секретной фразы с переходом без потерь, лимиты частоты."""
import ratelimit
import sdo_accounts


def test_passphrase_key_and_rotation(monkeypatch):
    monkeypatch.delenv("SDO_CRYPT_KEY", raising=False)
    monkeypatch.delenv("SDO_CRYPT_PASSPHRASE", raising=False)
    old = sdo_accounts.encrypt("cookie-old-0123456789")          # ключ от токена бота
    monkeypatch.setenv("SDO_CRYPT_PASSPHRASE", "капибара катит мяч")
    assert sdo_accounts.key_source() == "passphrase"
    assert sdo_accounts.decrypt(old) == "cookie-old-0123456789"   # старое читается
    assert sdo_accounts.needs_rotation(old)                       # и будет перешифровано
    new = sdo_accounts.encrypt("cookie-old-0123456789")
    assert not sdo_accounts.needs_rotation(new)
    monkeypatch.setenv("SDO_CRYPT_PASSPHRASE", "другая фраза")
    assert sdo_accounts.decrypt(new) is None                      # без фразы не прочитать


def test_rate_limit():
    ratelimit.reset()
    assert all(ratelimit.allow("submit", 1) for _ in range(6))
    assert not ratelimit.allow("submit", 1)
    assert ratelimit.allow("submit", 2)                            # у каждого свой счётчик
    ratelimit.reset()
