"""«Кайзер» (v4.45.0): обработчики WebApp разнесены по webapp/routes/*.
Каждый роутер подключён к приложению, а статика — последней (иначе она
перехватила бы /api)."""


def test_every_router_is_included_and_static_is_last():
    import webapp.server as server
    from webapp.routes import account, chat, deadlines, files, schedule, sdo

    registered = {(r.path, frozenset(r.methods)) for r in server.app.routes if getattr(r, "methods", None)}
    for module in (account, chat, deadlines, files, schedule, sdo):
        for r in module.router.routes:
            assert (r.path, frozenset(r.methods)) in registered, f"{module.__name__}: {r.path} не подключён"
    assert server.app.routes[-1].name == "static"
