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


def test_ratelimit_forgets_stale_keys(monkeypatch):
    """Ключи-IP с сайта не копятся вечно: при переполнении отжившие выкидываются."""
    ratelimit.reset()
    monkeypatch.setattr(ratelimit, "MAX_KEYS", 10)
    clock = [1000.0]
    monkeypatch.setattr(ratelimit.time, "monotonic", lambda: clock[0])
    for i in range(11):
        assert ratelimit.allow("site_search", -i - 1)
    clock[0] += 61
    assert ratelimit.allow("site_search", -100) and len(ratelimit._hits) == 1
    ratelimit.reset()
