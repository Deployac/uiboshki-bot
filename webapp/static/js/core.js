// Общее: Telegram, тема, api(), вкладки, утилиты — часть WebApp (раньше всё жило в одном index.html на 1945 строк).
// Файлы подключаются по порядку и делят глобальную область видимости.

const tg = window.Telegram ? window.Telegram.WebApp : null;
const BOT_USERNAME = "uiboshkibot"; // если бот переименуют — поменять тут

if (tg) {
  tg.ready();
  tg.expand();
  // Случайный свайп вниз не сворачивает приложение (Bot API 7.7), как у
  // @BotFather; закрыть — кнопкой «Закрыть».
  try { if (tg.disableVerticalSwipes) tg.disableVerticalSwipes(); } catch (e) {}
  try { tg.setHeaderColor("secondary_bg_color"); } catch (e) {}
  const tp = tg.themeParams || {};
  const root = document.documentElement.style;
  if (tp.bg_color)            root.setProperty("--bg", tp.bg_color);
  // Карточки должны отличаться от фона. Живой тест: из чата бота Telegram
  // дал серый secondary_bg_color, а с ярлыка «Домой» — такой же чёрный, как
  // фон, и карточки сливались. Берём первый цвет, отличный от фона, иначе
  // чуть светлее/темнее фона сами.
  const sameAsBg = c => !c || (tp.bg_color && c.toLowerCase() === tp.bg_color.toLowerCase());
  const card = [tp.section_bg_color, tp.secondary_bg_color].find(c => !sameAsBg(c))
    || (tp.bg_color ? (tg.colorScheme === "light" ? "#f2f2f7" : "#1c1c1e") : "");
  if (card) root.setProperty("--bg-card", card);
  if (tp.text_color)          root.setProperty("--text", tp.text_color);
  if (tp.hint_color)          root.setProperty("--hint", tp.hint_color);
  if (tp.button_color)        root.setProperty("--accent", tp.button_color);
  // Светлая тема Telegram: тёмные рамки и тяжёлая тень из тёмной палитры
  // смотрелись грубо (замечено в живом тесте) — делаем их светлыми.
  if (tg.colorScheme === "light") {
    root.setProperty("--border", tp.section_separator_color || "#e4e6ea");
    root.setProperty("--bg-raised", "#eceef1");
    root.setProperty("--shadow", "0 2px 10px rgba(0,0,0,0.06)");
  } else if (tp.section_separator_color) {
    root.setProperty("--border", tp.section_separator_color);
  }
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

function initData() {
  return tg ? tg.initData : "";
}

async function api(path, opts) {
  opts = opts || {};
  opts.headers = Object.assign({
    "X-Telegram-Init-Data": initData(),
    "Content-Type": "application/json",
  }, opts.headers || {});
  const resp = await fetch(path, opts);
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
  document.querySelectorAll(".view").forEach(v => v.classList.remove("active"));
  document.getElementById("view-" + name).classList.add("active");
  const menu = document.getElementById("more-menu");
  if (menu) menu.classList.remove("open");
  // СДО — своя кнопка внизу (и его экраны: предмет, ТК, задание); файлы и
  // дедлайны живут в меню «Ещё» — тогда подсвечена ☰
  const tab = ["sdo", "subject", "tk", "task"].includes(name) ? "sdo"
    : (["files", "deadlines"].includes(name) ? "more" : name);
  document.querySelectorAll("nav.tabs button").forEach(b => b.classList.toggle("active", b.dataset.tab === tab));
  haptic();
  if (name === "deadlines") loadDeadlines();
  if (name === "files") loadFiles();
  if (name === "search") { renderRecent(); loadPins().then(renderRecent); }
  if (name === "chat") requestAnimationFrame(syncNavHeight);
  if (tg && tg.BackButton) {
    tg.BackButton.offClick(closeFolder);
    tg.BackButton.offClick(sdoBack);
    const targetOpen = document.getElementById("target-view").style.display === "block";
    if (!(name === "search" && targetOpen)) tg.BackButton.hide();
  }
}

// ── Утилиты ───────────────────────────────────────────────────────────────

function escapeHtml(s) {
  return (s || "").replace(/[&<>"']/g, c => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
  })[c]);
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

