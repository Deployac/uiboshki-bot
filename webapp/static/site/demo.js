// Демо-режим приложения для сайта /about — подключается вместо SDK Telegram
// (webapp/routes/site.py: /about/demo). Само приложение — то же, что в
// Telegram; здесь только:
//   • заглушка Telegram.WebApp (тёмная тема, без знакомства и «Что нового»);
//   • время как в записанных данных — четверг, 8 октября, 10:05 МСК, и дальше
//     идёт само (иначе «сегодня» на телефоне и в данных разъедутся);
//   • ответы /api/… из site/demo.json — тестовые данные стенда, ничьих
//     настоящих данных там нет. Поиск расписания — настоящий (/about/api/…).
(function () {
  const REC_NOW = 1791443100000;
  const RealDate = Date;
  const shift = REC_NOW - RealDate.now();
  function DemoDate(...a) {
    if (!(this instanceof DemoDate)) return new RealDate(RealDate.now() + shift).toString();
    return a.length ? new RealDate(...a) : new RealDate(RealDate.now() + shift);
  }
  DemoDate.prototype = RealDate.prototype;
  DemoDate.now = () => RealDate.now() + shift;
  DemoDate.UTC = RealDate.UTC;
  DemoDate.parse = RealDate.parse;
  window.Date = DemoDate;

  const noop = () => {};
  const back = { show: noop, hide: noop, onClick: noop, offClick: noop };
  const cloud = { news_seen: "v5.20", onboarded_v1: "1" };
  window.Telegram = { WebApp: {
    initData: "demo", initDataUnsafe: { user: { id: 222, first_name: "Аня" } },
    colorScheme: "dark", themeParams: {}, platform: "ios", version: "8.0",
    isVersionAtLeast: () => true, ready: noop, expand: noop, onEvent: noop, offEvent: noop, setHeaderColor: noop,
    // как в Telegram на весь экран: сверху — место под вырез телефона на сайте
    disableVerticalSwipes: noop, requestFullscreen: noop, isFullscreen: true,
    safeAreaInset: { top: 44, bottom: 10 }, contentSafeAreaInset: { top: 0, bottom: 0 },
    BackButton: back, HapticFeedback: { impactOccurred: noop, notificationOccurred: noop, selectionChanged: noop },
    CloudStorage: { getItem(k, cb) { cb(null, cloud[k] || ""); }, setItem(k, v, cb) { cloud[k] = v; cb && cb(null, true); } },
    showConfirm: (t, cb) => cb(true), showAlert: (t, cb) => cb && cb(),
    openLink: (u) => window.open(u, "_blank", "noopener"), openTelegramLink: (u) => window.open(u, "_blank", "noopener"),
    downloadFile: noop, addToHomeScreen: noop, checkHomeScreenStatus: (cb) => cb && cb("unsupported"),
  } };

  // Телефон на сайте — iframe. iOS по-своему считает высоту iframe и место
  // для position: fixed: на коротком дне нижняя панель уезжала вверх, под ней
  // была чёрная пустота, а кнопки переставали нажиматься (живой тест 04.10).
  // Поэтому в демо прокручивается не окно, а body внутри экрана фиксированной
  // высоты; прокрутку приложения (window.scrollTo / scrollY) ведём туда же.
  const style = document.createElement("style");
  style.textContent = "html{height:100%;overflow:hidden}" +
    "body{height:100%;overflow-y:auto;-webkit-overflow-scrolling:touch;overscroll-behavior:contain}";
  document.head.appendChild(style);
  const scroller = () => document.body || document.documentElement;
  window.scrollTo = function (x, y) {
    const b = scroller();
    if (typeof x === "object" && x) b.scrollTo(x);
    else b.scrollTo(x || 0, y || 0);
  };
  window.scrollBy = function (x, y) { scroller().scrollBy(x, y); };
  try {
    Object.defineProperty(window, "scrollY", { configurable: true, get: () => scroller().scrollTop });
    Object.defineProperty(window, "pageYOffset", { configurable: true, get: () => scroller().scrollTop });
  } catch (e) {}

  const realFetch = window.fetch.bind(window);
  const fixtures = realFetch("site/demo.json").then(r => r.json()).then(d => d.fx);
  const reply = (body, status) => new Response(JSON.stringify(body), {
    status: status || 200, headers: { "Content-Type": "application/json" } });
  const nope = () => reply({ detail: "в демо это не работает — открой бота в Telegram" }, 403);

  window.fetch = async function (input, init) {
    const u = new URL(typeof input === "string" ? input : input.url, location.href);
    if (!u.pathname.startsWith("/api/")) return realFetch(input, init);
    const method = ((init && init.method) || "GET").toUpperCase();
    // поиск расписания любой группы, преподавателя, аудитории — настоящий
    if (method === "GET" && (u.pathname === "/api/search" || u.pathname.startsWith("/api/target/"))) {
      return realFetch("/about" + u.pathname + u.search);
    }
    const fx = await fixtures;
    if (method === "GET") {
      const hit = fx["GET " + u.pathname + u.search] || fx["GET " + u.pathname];
      return hit !== undefined ? reply(hit) : nope();
    }
    if (u.pathname.startsWith("/api/sdo/goal/")) {
      let label = "";
      try { label = JSON.parse(init.body).label; } catch (e) {}
      const hit = fx["POST " + u.pathname + "|" + label];
      return hit ? reply(hit) : nope();
    }
    if (u.pathname === "/api/chat") {
      await new Promise(r => setTimeout(r, 1400));          // «думает», как настоящий
      return reply(fx["POST /api/chat"]);
    }
    if (u.pathname === "/api/notify") return reply(fx["GET /api/notify"]);
    return nope();                                            // сдача работ, загрузка, удаление — только в боте
  };
})();
