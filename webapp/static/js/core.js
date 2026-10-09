// Общее: Telegram, тема, api(), вкладки, утилиты — часть WebApp (раньше всё жило в одном index.html на 1945 строк).
// Файлы подключаются по порядку и делят глобальную область видимости.

const tg = window.Telegram ? window.Telegram.WebApp : null;
// Вне Telegram (PWA, браузер, будущее приложение — этап 2) вход — токеном
// сессии устройства: «Войти через Telegram» → подтвердить в боте (webapp/routes/auth.py).
const IN_TG = !!(tg && tg.initData);
function readToken() { try { return localStorage.getItem("uib_token") || ""; } catch (e) { return ""; } }
function saveToken(t) { try { if (t) localStorage.setItem("uib_token", t); else localStorage.removeItem("uib_token"); } catch (e) {} }
// Вход через VK/Яндекс: сервер вернул сюда с токеном во фрагменте (/app#token=…,
// webapp/routes/auth.py) — сохранить и убрать из адреса, чтобы не остался в истории.
// Токен берём, только если вход начат в этом браузере (startOAuth, 15 минут):
// иначе по присланной ссылке /app#token=<чужой> человек оказывался в чужом
// аккаунте и мог вставить туда свой вход в СДО (ревью безопасности 09.10).
function oauthPending() {
  try {
    const at = +localStorage.getItem("uib_oauth_at") || 0;
    localStorage.removeItem("uib_oauth_at");
    return Date.now() - at < 15 * 60 * 1000;
  } catch (e) { return false; }
}
if (!IN_TG && location.hash.startsWith("#token=")) {
  if (oauthPending()) saveToken(decodeURIComponent(location.hash.slice(7)));
  history.replaceState(null, "", location.pathname + location.search);
}
const APP_TOKEN = IN_TG ? "" : readToken();
// Корень открыли в обычном браузере без входа — это гость по ссылке
// www.uiboshki.ru: ему нужен сайт-презентация, а не приложение без входа.
if (!IN_TG && !APP_TOKEN && (location.pathname === "/" || location.pathname === "/index.html")) {
  location.replace("/about");
}
const NEED_LOGIN = !IN_TG && !APP_TOKEN;      // /app без входа — экран «Войти»
// PWA: service worker (sw.js — оболочка и последние данные без сети) — только вне Telegram
if (!IN_TG && "serviceWorker" in navigator && location.protocol === "https:") {
  navigator.serviceWorker.register("/sw.js").catch(() => {});
}
// PWA с экрана «Домой» на iPhone — на весь экран, строка с часами поверх
// (black-translucent): без отступа шапка уезжала под часы (скрин владельца,
// iPhone 16 Pro). Тот же режим, что полный экран Telegram: отступы — из
// env(safe-area-inset-*) (app.css, html.standalone).
if (!IN_TG && (navigator.standalone || (window.matchMedia && matchMedia("(display-mode: standalone)").matches))) {
  document.documentElement.classList.add("standalone", "fullscreen");
}
// Тема вне Telegram — системная (тёмная/светлая), как у остальных приложений телефона
if (!tg || !tg.initData) {
  const mq = window.matchMedia ? window.matchMedia("(prefers-color-scheme: light)") : null;
  const sys = () => {
    const light = !!(mq && mq.matches), root = document.documentElement.style;
    document.documentElement.dataset.theme = light ? "light" : "dark";
    const pal = light ? { "--bg": "#f5f6f8", "--bg-card": "#ffffff", "--text": "#15171c", "--hint": "#6b7280",
      "--border": "#e4e6ea", "--bg-raised": "#eceef1", "--shadow": "0 2px 10px rgba(0,0,0,0.06)" } : {};
    ["--bg", "--bg-card", "--text", "--hint", "--border", "--bg-raised", "--shadow"].forEach(k =>
      pal[k] ? root.setProperty(k, pal[k]) : root.removeProperty(k));
  };
  sys();
  if (mq && mq.addEventListener) mq.addEventListener("change", sys);
}
// Имя бота и группы сервер подставляет в страницу (config.py: BOT_USERNAME,
// GROUP_NAME); без него (файл открыт напрямую) — как у УИБО-03-24.
const APP_CONFIG = window.APP_CONFIG || {};
const BOT_USERNAME = APP_CONFIG.bot || "uiboshkibot";
const GROUP_NAME = APP_CONFIG.group || "УИБО-03-24";
// Канал бота и «Написать нам» (config.py: CHANNEL_URL, CONTACT_URL); пусто — плитка говорит «Скоро»
const CHANNEL_URL = APP_CONFIG.channel || "";
const CONTACT_URL = APP_CONFIG.contact || "";
const GUIDE_URL = APP_CONFIG.guide || "";          // пост-гайд «как подключить СДО» в канале

if (tg) {
  tg.ready();
  tg.expand();
  // Случайный свайп вниз не сворачивает приложение (Bot API 7.7), как у
  // @BotFather; закрыть — кнопкой «Закрыть».
  try { if (tg.disableVerticalSwipes) tg.disableVerticalSwipes(); } catch (e) {}
  try { tg.setHeaderColor("secondary_bg_color"); } catch (e) {}
  applyTheme();
  // Тему Telegram можно переключить, не закрывая приложение (или она
  // меняется сама — «как в системе» вечером) — перекрашиваемся сразу.
  try { tg.onEvent("themeChanged", applyTheme); } catch (e) {}
}

// Цвета приложения — из темы Telegram (тёмная/светлая, свой акцент).
// data-theme на <html> — для мест, где светлой теме нужен свой цвет (app.css).
function applyTheme() {
  if (!IN_TG) return;                  // вне Telegram — системная тема (выше)
  const tp = tg.themeParams || {};
  const root = document.documentElement.style;
  const light = tg.colorScheme === "light";
  document.documentElement.dataset.theme = light ? "light" : "dark";
  const set = (name, value) => value ? root.setProperty(name, value) : root.removeProperty(name);
  set("--bg", tp.bg_color);
  // Карточки должны отличаться от фона. Живой тест: из чата бота Telegram
  // дал серый secondary_bg_color, а с ярлыка «Домой» — такой же чёрный, как
  // фон, и карточки сливались. Берём первый цвет, отличный от фона, иначе
  // чуть светлее/темнее фона сами.
  const sameAsBg = c => !c || (tp.bg_color && c.toLowerCase() === tp.bg_color.toLowerCase());
  const card = [tp.section_bg_color, tp.secondary_bg_color].find(c => !sameAsBg(c))
    || (tp.bg_color ? (light ? "#f2f2f7" : "#1c1c1e") : "");
  set("--bg-card", card);
  set("--text", tp.text_color);
  set("--hint", tp.hint_color);
  set("--accent", tp.button_color);
  // Светлая тема Telegram: тёмные рамки и тяжёлая тень из тёмной палитры
  // смотрелись грубо (замечено в живом тесте) — делаем их светлыми.
  set("--border", light ? (tp.section_separator_color || "#e4e6ea") : tp.section_separator_color);
  set("--bg-raised", light ? "#eceef1" : "");
  set("--shadow", light ? "0 2px 10px rgba(0,0,0,0.06)" : "");
}

// Полный экран на телефоне (Telegram 8.0+): без шапки Telegram, как
// отдельное приложение. Отступы под «чёлку»/полоску (safeAreaInset) и под
// плавающие кнопки Telegram сверху (contentSafeAreaInset) — в CSS-переменные
// --safe-top/--safe-bottom, по ним сдвигаются шапка и вкладки (app.css).
function syncSafeArea() {
  if (!tg) return;
  const sa = tg.safeAreaInset || {}, ca = tg.contentSafeAreaInset || {};
  const root = document.documentElement.style;
  root.setProperty("--safe-top", ((sa.top || 0) + (ca.top || 0)) + "px");
  root.setProperty("--safe-bottom", ((sa.bottom || 0) + (ca.bottom || 0)) + "px");
}
// Живой тест: с ярлыка «Домой» Telegram открывает приложение уже на весь
// экран (Launch Mode в BotFather) — requestFullscreen тогда отвечает
// fullscreenFailed «ALREADY_FULLSCREEN», и мы снимали отступы: шапка
// налезала на часы. Класс держим по tg.isFullscreen, а не по ответу.
function syncFullscreen() {
  document.documentElement.classList.toggle("fullscreen", !!tg.isFullscreen);
  syncSafeArea();
}
if (tg && tg.isVersionAtLeast && tg.isVersionAtLeast("8.0") && ["ios", "android"].includes(tg.platform)) {
  try {
    tg.onEvent("safeAreaChanged", syncSafeArea);
    tg.onEvent("contentSafeAreaChanged", syncSafeArea);
    tg.onEvent("fullscreenChanged", syncFullscreen);
    tg.onEvent("fullscreenFailed", syncFullscreen);
    if (!tg.isFullscreen) tg.requestFullscreen();
    syncFullscreen();
  } catch (e) {}
}

// Высота нижней панели (--nav-h, chat.js: syncNavHeight) меняется и без
// resize: Telegram присылает отступ под полоску «Домой» уже после загрузки
// (safeAreaChanged) — панель вырастала, а «＋», тост и низ страницы
// оставались под ней (ночь 09.10). Следим за самой панелью.
if (window.ResizeObserver) {
  new ResizeObserver(() => { if (typeof syncNavHeight === "function") syncNavHeight(); })
    .observe(document.querySelector("nav.tabs"), { box: "border-box" });   // отступ — это padding
}

function initData() {
  return tg ? tg.initData : "";
}

async function api(path, opts) {
  opts = opts || {};
  opts.headers = Object.assign({
    "X-Telegram-Init-Data": initData(),
    "Content-Type": "application/json",
  }, APP_TOKEN ? { "Authorization": "Bearer " + APP_TOKEN } : {}, opts.headers || {});
  const resp = await fetch(path, opts);
  if (resp.status === 401 && APP_TOKEN) {        // сессию отозвали («выйти везде») — заново войти
    saveToken("");
    location.replace("/app");
  }
  if (!resp.ok) {
    const body = await resp.text();
    let detail = "";
    try { detail = JSON.parse(body).detail; } catch (e) {}
    throw new Error(typeof detail === "string" && detail ? detail : "ошибка сервера (" + resp.status + ")");
  }
  return resp.json();
}

function haptic(kind) {
  if (tg && tg.HapticFeedback) {
    try {
      if (kind === "success") tg.HapticFeedback.notificationOccurred("success");
      else tg.HapticFeedback.impactOccurred("light");
    } catch (e) {}
  }
}

// ── Табы ──────────────────────────────────────────────────────────────────

function switchTab(name) {
  const focused = document.activeElement;
  if (focused && /^(INPUT|TEXTAREA)$/.test(focused.tagName)) focused.blur();   // убрать клавиатуру
  document.querySelectorAll(".view").forEach(v => v.classList.remove("active"));
  document.getElementById("view-" + name).classList.add("active");
  // «Доброе утро, …» — только на «Сегодня», на остальных вкладках сразу к делу
  // (дизайн-ревью, п. 9)
  document.body.classList.toggle("compact-head", name !== "today");
  const menu = document.getElementById("more-menu");
  if (menu) menu.classList.remove("open");
  // СДО — своя кнопка внизу (и его экраны: предмет, ТК, задание); файлы и
  // дедлайны живут в меню «Ещё» — тогда подсвечена ☰
  const tab = ["sdo", "subject", "tk", "pos", "task"].includes(name) ? "sdo"
    : (["files", "deadlines"].includes(name) ? "more" : name);
  document.querySelectorAll("nav.tabs button").forEach(b => b.classList.toggle("active", b.dataset.tab === tab));
  haptic();
  if (name === "deadlines") loadDeadlines();
  if (name === "files") loadFiles();
  if (name === "search") { renderRecent(); loadPins().then(renderRecent); }
  if (name === "chat") requestAnimationFrame(() => { syncNavHeight(); scrollChatToEnd(); });
  if (tg && tg.BackButton) {
    // снимаем все «Назад» экранов (как NESTED в main.js): оставленный closeTarget
    // закрывал скрытый экран расписания из поиска, уйди хоть в чат
    [closeFolder, sdoBack, closeTarget].forEach(fn => tg.BackButton.offClick(fn));
    const targetOpen = document.getElementById("target-view").style.display === "block";
    if (name === "search" && targetOpen) { tg.BackButton.onClick(closeTarget); tg.BackButton.show(); }
    else tg.BackButton.hide();
  }
}

// ── Утилиты ───────────────────────────────────────────────────────────────

// Пустой экран «по-хорошему» (пар нет, всё сдано, дедлайнов нет) — с
// капибарой с логотипа, а не просто серой строкой.
// Клавиатура на телефоне: «Ввод» в поле поиска и нажатие мимо поля её
// убирают — отдельной кнопки «скрыть» в Telegram нет.
document.addEventListener("keydown", (e) => {
  const t = e.target;
  if (e.key === "Enter" && t && t.tagName === "INPUT" && t.classList.contains("searchbox")) t.blur();
});
// Листы снизу смахиваются вниз, как в Telegram, — раньше закрывались только
// кнопкой («Что нового» — только «Круто», заметил владелец), а палец листал
// страницу под листом. Тянем, только когда лист промотан до верха.
const sheetDrag = { s: null };
document.addEventListener("touchstart", (e) => {
  const sheet = e.target.closest && e.target.closest(".sheet-backdrop.open .sheet");
  sheetDrag.s = sheet ? { sheet: sheet, y0: e.touches[0].clientY, t0: Date.now(), dy: 0, on: false } : null;
}, { passive: true });
document.addEventListener("touchmove", (e) => {
  const t = e.target.closest ? e.target : null;
  if (t && t.closest(".sheet-backdrop.open") && !t.closest(".sheet")) { e.preventDefault(); return; }   // фон не листаем
  const d = sheetDrag.s;
  if (!d) return;
  const dy = e.touches[0].clientY - d.y0;
  if (!d.on) {
    if (Math.abs(dy) < 8) return;
    if (dy < 0 || d.sheet.scrollTop > 0) { sheetDrag.s = null; return; }   // это прокрутка листа, не свайп
    d.on = true;
    d.sheet.style.transition = "none";
  }
  e.preventDefault();
  d.dy = Math.max(0, dy);
  d.sheet.style.transform = "translateY(" + d.dy + "px)";
}, { passive: false });
document.addEventListener("touchend", () => {
  const d = sheetDrag.s;
  sheetDrag.s = null;
  if (!d || !d.on) return;
  const fast = d.dy > 40 && d.dy / Math.max(1, Date.now() - d.t0) > 0.6;
  d.sheet.style.transition = "transform .18s ease";
  if (d.dy > 110 || fast) {
    d.sheet.style.transform = "translateY(100%)";
    setTimeout(() => { closeSheet(d.sheet.closest(".sheet-backdrop").id); d.sheet.style.transform = ""; d.sheet.style.transition = ""; }, 180);
  } else {
    d.sheet.style.transform = "";
    setTimeout(() => { d.sheet.style.transition = ""; }, 200);
  }
});

document.addEventListener("touchstart", (e) => {
  const a = document.activeElement;
  if (!a || !/^(INPUT|TEXTAREA)$/.test(a.tagName)) return;
  const keep = e.target.closest && e.target.closest("input, textarea, button, label, select, .chip, .pill");
  if (keep && !keep.closest(".tabs")) return;      // нижнее меню клавиатуру убирает
  a.blur();
}, { passive: true });

function capyEmpty(title, sub, pose) {
  return '<div class="empty capy-empty"><span class="capy-pose capy-' + (pose || "joy") + '" aria-hidden="true"></span>' +
    '<b>' + title + '</b>' + (sub ? '<span>' + sub + '</span>' : '') + '</div>';
}

// «Не загрузилось» — грустная капибара вместо голой строки
function capyError(msg, extra) {
  return '<div class="empty capy-empty err"><span class="capy-pose capy-sad" aria-hidden="true"></span>' +
    '<b>Не загрузилось</b><span>' + escapeHtml(msg || "") + '</span>' + (extra || "") + '</div>';
}

// Капибара по времени суток: утро — кофе, день — ноутбук, вечер — книга, ночь — спит
function capyForHour(hour) {
  if (hour >= 5 && hour < 12) return "morning";
  if (hour >= 12 && hour < 17) return "day";
  if (hour >= 17 && hour < 23) return "evening";
  return "night";
}

function hideSplash() {
  const s = document.getElementById("splash");
  if (s) s.classList.add("gone");
}

function escapeHtml(s) {
  return (s || "").replace(/[&<>"']/g, c => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
  })[c]);
}

// Даты по-человечески (дизайн-ревью, п. 15): вместо голых «8.10» и «к 09.10»
// — «чт, 8 окт · через 6 дн.», чтобы не считать день недели и сколько осталось.
// iso — «ГГГГ-ММ-ДД»; opts.time — «ЧЧ:ММ» (23:59 у дальних дат не пишем — это
// «до конца дня»), opts.today — «сегодня» в ISO (по умолчанию — дата телефона).
// Ближние: «сегодня · 23:59», «завтра · 09:00», «вчера»; дальше месяца — без «через».
const MONTHS_SHORT = ["янв", "фев", "мар", "апр", "мая", "июн", "июл", "авг", "сен", "окт", "ноя", "дек"];
const WEEKDAYS_SHORT = ["вс", "пн", "вт", "ср", "чт", "пт", "сб"];

function isoDays(iso) {          // дни от эпохи — без сдвигов часовых поясов и перевода часов
  const p = String(iso).slice(0, 10).split("-").map(Number);
  return Math.round(Date.UTC(p[0], p[1] - 1, p[2]) / 86400000);
}

function humanDate(iso, opts) {
  opts = opts || {};
  const now = new Date();
  const today = opts.today ? isoDays(opts.today) : Math.round(Date.UTC(now.getFullYear(), now.getMonth(), now.getDate()) / 86400000);
  const days = isoDays(iso) - today;
  const d = new Date(isoDays(iso) * 86400000);
  const date = WEEKDAYS_SHORT[d.getUTCDay()] + ", " + d.getUTCDate() + " " + MONTHS_SHORT[d.getUTCMonth()];
  let text;
  if (days === 0) text = "сегодня";
  else if (days === 1) text = "завтра";
  else if (days === -1) text = "вчера";
  else if (days === 7) text = date + " · через неделю";
  else if (days > 1 && days <= 30) text = date + " · через " + days + " дн.";
  else if (days < -1 && days >= -30) text = date + " · " + (-days) + " дн. назад";
  else text = date;
  const near = Math.abs(days) <= 1;
  if (opts.time && (near || opts.time !== "23:59")) text += " · " + opts.time;
  return text;
}

// «Открыть» у файла: бот присылает его в чат, кнопка показывает, что
// происходит (⏳ → ✓ В чате). Если запрос не прошёл — старый путь через
// диплинк t.me/<бот>?start=… (там «/start …» бот сразу стирает).
async function sendToChat(path, deeplink, btn) {
  const label = btn ? btn.innerHTML : "";
  if (btn) { btn.disabled = true; btn.classList.add("sending"); btn.innerHTML = icon("clock"); }
  try {
    await api(path, { method: "POST" });
    haptic("success");
    if (btn) { btn.classList.remove("sending"); btn.classList.add("sent"); btn.innerHTML = icon("check") + " В чате"; }
    showToast("📨 Файл в чате с ботом");
  } catch (e) {
    if (btn) btn.classList.remove("sending");
    const link = "https://t.me/" + BOT_USERNAME + "?start=" + deeplink;
    if (tg && tg.openTelegramLink) tg.openTelegramLink(link); else window.open(link, "_blank");
  } finally {
    if (btn) setTimeout(() => { btn.disabled = false; btn.classList.remove("sent"); btn.innerHTML = label; }, 2500);
  }
}


// ── Вход вне Telegram (этап 2: PWA и своё приложение) ───────────────────────
// Код входа → ссылка в бота → «Да, это я» → токен. Ждём подтверждения до 10 минут.
let loginCode = null, loginTimer = null;

function showLogin() {
  const box = document.getElementById("login");
  box.classList.add("open");
  box.innerHTML = '<div class="login-card"><svg class="login-capy" aria-hidden="true"><use href="#i-capy"/></svg>' +
    '<h2>УИБО-бот</h2><p>Расписание, дедлайны, баллы СДО и лекции твоей группы.</p>' +
    '<button class="primary" id="login-btn" onclick="startLogin()">Войти через Telegram</button>' +
    '<p class="hint" id="login-hint">Бот спросит «Это ты?» — нажми «Да». Один раз на этом устройстве.</p>' +
    '<div id="login-more"></div></div>';
  // VK ID и Яндекс ID — если на сервере есть их ключи (/api/auth/providers)
  fetch("/api/auth/providers").then(r => r.json()).then(res => {
    const box = document.getElementById("login-more");
    if (!box || !res.items || !res.items.length) return;
    box.innerHTML = '<p class="hint">или</p>' + res.items.map(p =>
      '<button class="ghost" onclick="startOAuth(\'' + p.id + '\')">Войти через ' + escapeHtml(p.name) + '</button>').join("") +
      '<p class="hint">Уже пользуешься через Telegram? Войди им, а VK или Яндекс привяжи в «Ещё → Безопасность» — ' +
      'иначе получится второй, пустой аккаунт.</p>';
  }).catch(() => {});
}

// VK/Яндекс: уходим к провайдеру в этом же окне, назад — /app#token=…
async function startOAuth(provider) {
  try {
    const res = await fetch("/api/auth/" + provider + "/start", { method: "POST", headers: { "Content-Type": "application/json" },
                                                                   body: JSON.stringify({ client: "web" }) });
    if (!res.ok) throw new Error();
    try { localStorage.setItem("uib_oauth_at", String(Date.now())); } catch (e) {}
    location.href = (await res.json()).url;
  } catch (e) {
    document.getElementById("login-hint").textContent = "Не получилось начать вход — попробуй через минуту.";
  }
}

async function startLogin() {
  const btn = document.getElementById("login-btn"), hint = document.getElementById("login-hint");
  btn.disabled = true;
  try {
    const res = await fetch("/api/auth/start", { method: "POST" }).then(r => r.ok ? r.json() : Promise.reject(r));
    loginCode = res.code;
    window.open(res.link, "_blank");
    hint.textContent = "Открыл бота — нажми там «Да, это я», а потом вернись сюда.";
    btn.textContent = "Открыть бота ещё раз";
    btn.disabled = false;
    btn.onclick = () => window.open(res.link, "_blank");
    clearInterval(loginTimer);
    loginTimer = setInterval(pollLogin, 2000);
  } catch (e) {
    btn.disabled = false;
    hint.textContent = "Не получилось начать вход — попробуй через минуту.";
  }
}

async function pollLogin() {
  if (!loginCode) return;
  let res;
  try {
    res = await fetch("/api/auth/poll", { method: "POST", headers: { "Content-Type": "application/json" },
                                          body: JSON.stringify({ code: loginCode }) }).then(r => r.json());
  } catch (e) { return; }
  if (res.status === "ok") {
    clearInterval(loginTimer);
    saveToken(res.token);
    location.replace("/app");
  } else if (res.status !== "wait") {
    clearInterval(loginTimer);
    loginCode = null;
    document.getElementById("login-hint").textContent =
      res.status === "denied" ? "Вход отклонён в боте." : "Ссылка устарела — нажми «Войти» ещё раз.";
    const btn = document.getElementById("login-btn");
    btn.textContent = "Войти через Telegram";
    btn.onclick = startLogin;
  }
}
