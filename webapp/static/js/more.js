// Меню «Ещё» (☰ в нижней панели), свой вход в СДО и сдача работ — часть WebApp.
// Файлы подключаются по порядку и делят глобальную область видимости.

// ── Меню «Ещё» ────────────────────────────────────────────────────────────

function toggleMore(show) {
  const menu = document.getElementById("more-menu");
  const open = show === undefined ? !menu.classList.contains("open") : show;
  menu.classList.toggle("open", open);
  document.getElementById("more-btn").classList.toggle("open", open);
  if (open) { syncNavHeight(); haptic(); loadSdoStatus(); }
}

function closeSheet(id) {
  document.getElementById(id).classList.remove("open");
}

// Подписка на расписание и дедлайны в календаре телефона (как /calendar в боте)
async function copyCalendarLink() {
  try {
    const data = await api("/api/calendar/link");
    const url = location.origin + data.ics_path;
    try { await navigator.clipboard.writeText(url); } catch (e) { prompt("Ссылка на календарь:", url); return; }
    haptic("success");
    showToast("🗓 Ссылка скопирована — Календарь → Добавить подписку");
  } catch (e) {
    showToast("Не вышло: " + e.message);
  }
}

// ── СДО: статус и подключение ─────────────────────────────────────────────

let sdoState = { state: "off" };

async function loadSdoStatus() {
  try { sdoState = await api("/api/sdo/status"); } catch (e) { return sdoState; }
  const sq = document.getElementById("more-sdo");
  sq.classList.toggle("badge", sdoState.state !== "off");
  sq.classList.toggle("bad", sdoState.state === "expired");
  return sdoState;
}

function agoText(iso) {
  if (!iso) return "";
  const min = Math.max(0, Math.round((Date.now() - new Date(iso.replace(" ", "T") + "Z")) / 60000));
  if (min < 1) return "Проверено только что";
  if (min < 60) return "Проверено " + min + " мин назад";
  return "Проверено " + Math.round(min / 60) + " ч назад";
}

function statusCard(dot, title, sub, cls) {
  return '<div class="st-card ' + (cls || "") + '"><span class="st-dot ' + dot + '"></span>' +
    '<div><b>' + title + '</b><div class="s">' + sub + '</div></div></div>';
}

async function openSdoSheet() {
  document.getElementById("sdo-sheet").classList.add("open");
  renderSdo();
  await loadSdoStatus();
  renderSdo();
}

function renderSdo(connecting) {
  const box = document.getElementById("sdo-body");
  const lock = '<div class="lock">🔒 Вход хранится зашифрованным и используется только по твоей команде. Отключить — одной кнопкой в любой момент.</div>';
  if (connecting) {
    box.innerHTML =
      '<h3>Подключить СДО</h3>' +
      '<ol class="steps">' +
        '<li><span>Открой <b>online-edu.mirea.ru</b> на компьютере и войди в свой аккаунт</span></li>' +
        '<li><span>F12 → Application → Cookies → строка <b>MoodleSession</b></span></li>' +
        '<li><span>Скопируй значение и вставь сюда</span></li>' +
      '</ol>' +
      '<input class="searchbox" id="sdo-cookie" placeholder="Вставь MoodleSession…" autocomplete="off" autocapitalize="off" spellcheck="false">' +
      '<div class="lock">🔒 Это как «оставаться в системе». Значение сразу шифруется, в переписке и логах не остаётся.</div>' +
      '<button class="primary" id="sdo-save" onclick="connectSdo()">Проверить и сохранить</button>' +
      '<button class="ghost" onclick="renderSdo()">Позже</button>';
    return;
  }
  if (sdoState.state === "ok") {
    box.innerHTML = '<h3>🎓 СДО</h3>' +
      statusCard("ok", "Подключено, работает", sdoState.shared ? "Вход старосты из настроек бота" : agoText(sdoState.checked_at)) +
      '<p class="sheet-hint">У дедлайнов из СДО есть кнопка «📤 Сдать»: выбираешь файл — бот загружает его в нужное задание.</p>' +
      (sdoState.shared ? '' : '<button class="ghost danger" onclick="disconnectSdo()">Отключить СДО</button>');
  } else if (sdoState.state === "expired") {
    box.innerHTML = '<h3>🎓 СДО</h3>' +
      statusCard("bad", "Вход устарел", "СДО разлогинил сессию — подключи заново", "bad") +
      '<button class="primary" onclick="renderSdo(true)">Подключить заново</button>' +
      '<button class="ghost danger" onclick="disconnectSdo()">Убрать</button>';
  } else {
    box.innerHTML = '<h3>🎓 СДО</h3>' +
      statusCard("off", "Не подключено", "Дедлайны группы видны и без этого") +
      '<p class="sheet-hint">Подключи свой вход в СДО — и сдавай работы прямо отсюда: выбрал файл → «Сдать» → готово.</p>' +
      lock + '<button class="primary" onclick="renderSdo(true)">Подключить СДО</button>';
  }
}

async function connectSdo() {
  const input = document.getElementById("sdo-cookie");
  const btn = document.getElementById("sdo-save");
  if (!input.value.trim()) { input.focus(); return; }
  btn.disabled = true; btn.textContent = "Проверяю…";
  try {
    sdoState = await api("/api/sdo/connect", { method: "POST", body: JSON.stringify({ cookie: input.value }) });
    input.value = "";
    haptic("success");
    renderSdo(); loadSdoStatus(); loadDeadlines();
  } catch (e) {
    btn.disabled = false; btn.textContent = "Проверить и сохранить";
    showToast("⚠️ " + e.message);
  }
}

async function disconnectSdo() {
  if (!(await confirmDialog("Отключить СДО? Сдавать работы отсюда будет нельзя, пока не подключишь снова."))) return;
  try {
    sdoState = await api("/api/sdo/disconnect", { method: "POST" });
    renderSdo(); loadSdoStatus();
  } catch (e) {
    showToast("Не вышло: " + e.message);
  }
}

// ── Сдача работы ──────────────────────────────────────────────────────────

const SUBMIT_MAX_MB = 20;
let submitting = { item: null, file: null, data: "" };

async function openSubmit(id) {
  const item = deadlineIndex[id];
  if (!item) return;
  haptic();
  if (sdoState.state === "off" || sdoState.state === "expired") await loadSdoStatus();
  if (sdoState.state !== "ok") { openSdoSheet(); return; }
  submitting = { item: item, file: null, data: "" };
  document.getElementById("submit-sheet").classList.add("open");
  renderSubmit();
}

function submitHead() {
  const it = submitting.item;
  return '<h3>📤 Сдать работу</h3><div class="sub-task"><b>' + escapeHtml(it.subject) + '</b>' +
    '<div class="s">до ' + escapeHtml(it.due_date.split("-").reverse().slice(0, 2).join(".")) +
    (it.due_time ? " · " + escapeHtml(it.due_time) : "") + '</div></div>';
}

function fileSize(bytes) {
  return bytes > 1024 * 1024 ? (bytes / 1024 / 1024).toFixed(1).replace(".", ",") + " МБ" : Math.max(1, Math.round(bytes / 1024)) + " КБ";
}

function renderSubmit(state, info) {
  const box = document.getElementById("submit-body");
  const f = submitting.file;
  if (state === "done") {
    box.innerHTML = '<div class="sub-done"><div class="big">✅</div><h3>Отправлено</h3>' +
      '<p class="sheet-hint">' + escapeHtml(submitting.item.subject) + ' · ' + escapeHtml(f.name) +
      (info && info.status ? '<br>Статус в СДО: «' + escapeHtml(info.status) + '»' : '') + '</p>' +
      '<button class="primary" onclick="openLink(' + escapeHtml(JSON.stringify(submitting.item.description)) + ')">Открыть в СДО</button>' +
      '<button class="ghost" onclick="closeSheet(\'submit-sheet\')">Готово</button></div>';
    return;
  }
  if (!f) {
    box.innerHTML = submitHead() +
      '<div class="fpick" onclick="document.getElementById(\'submit-file\').click()"><span class="ic">📎</span>' +
      '<div><b>Выбрать файл</b><div class="s">до ' + SUBMIT_MAX_MB + ' МБ</div></div><span class="go">Обзор</span></div>' +
      '<button class="primary" disabled>Загрузить в СДО</button>';
    return;
  }
  const busy = state === "sending";
  box.innerHTML = submitHead() +
    '<div class="fpick chosen"><span class="ic">📄</span><div><b>' + escapeHtml(f.name) + '</b>' +
    '<div class="s">' + fileSize(f.size) + ' · готово к отправке</div></div>' +
    (busy ? '' : '<button class="x" onclick="submitting.file = null; renderSubmit()" aria-label="Убрать">✕</button>') + '</div>' +
    '<div class="lock">⚠️ Файл уйдёт преподавателю от твоего имени. Проверь название и работу.</div>' +
    '<button class="primary" id="submit-go" onclick="sendSubmission()"' + (busy ? ' disabled' : '') + '>' +
    (busy ? 'Загружаю в СДО…' : 'Отправить на проверку') + '</button>' +
    (busy ? '' : '<button class="ghost" onclick="closeSheet(\'submit-sheet\')">Отмена</button>');
}

document.getElementById("submit-file").addEventListener("change", e => {
  const file = e.target.files[0];
  e.target.value = "";
  if (!file) return;
  if (file.size > SUBMIT_MAX_MB * 1024 * 1024) { showToast("Файл больше " + SUBMIT_MAX_MB + " МБ"); return; }
  const reader = new FileReader();
  reader.onload = () => {
    submitting.file = { name: file.name || "работа", size: file.size };
    submitting.data = String(reader.result).split(",")[1] || "";
    haptic();
    renderSubmit();
  };
  reader.readAsDataURL(file);
});

async function sendSubmission() {
  renderSubmit("sending");
  try {
    const res = await api("/api/sdo/submit", { method: "POST", body: JSON.stringify({
      deadline_id: submitting.item.id, name: submitting.file.name, data: submitting.data }) });
    haptic("success");
    renderSubmit("done", res);
  } catch (e) {
    renderSubmit();
    showToast("⚠️ " + e.message);
    if (/подключи/.test(e.message)) { loadSdoStatus(); }
  }
}

loadSdoStatus();
