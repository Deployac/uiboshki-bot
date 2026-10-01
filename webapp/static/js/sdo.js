// СДО → Баллы: предметы семестра, предмет подробно, «Текущий контроль» — часть WebApp.
// Файлы подключаются по порядку и делят глобальную область видимости.

let sdoData = null;            // /api/sdo/grades
let sdoCourse = null;          // /api/sdo/grades/{id}
let sdoView = "sdo";           // sdo → subject → tk
let tkFilter = "all";

// Цвет категории БРС — по названию (названия берутся из журнала курса)
function catColor(name) {
  const n = (name || "").toLowerCase();
  if (n.includes("текущ")) return "var(--s-tk)";
  if (n.includes("посещ")) return "var(--s-pos)";
  if (n.includes("семестр") || n.includes("экзам") || n.includes("промежут")) return "var(--s-sk)";
  if (n.includes("труд")) return "var(--s-td)";
  if (n.includes("достиж")) return "var(--s-dost)";
  return "var(--s-dop)";
}

function fmtNum(x) {
  return (Math.round(x * 10) / 10).toString().replace(".", ",");
}

function needText(c) {
  if (c.closed && !c.need) return "✓ все пороги взяты";
  if (c.closed) return "✓ закрыт · до «" + escapeHtml(c.need_label) + "» ещё <b>" + fmtNum(c.need) + "</b>";
  return (c.kind === "credit" ? "до зачёта" : "до «" + escapeHtml(c.need_label) + "»") + " ещё <b>" + fmtNum(c.need) + "</b>";
}

// Полоска суммы: доли категорий от 130 и пороги
function scoreBar(c, cls) {
  const seg = c.categories.filter(k => k.score > 0)
    .map(k => '<i style="width:' + Math.min(100, k.score / c.max * 100).toFixed(1) + '%;background:' + catColor(k.name) + '"></i>').join("");
  const ticks = c.marks.map(m => '<span class="tk" style="left:' + (m.at / c.max * 100).toFixed(1) + '%"></span>').join("");
  return '<span class="sbar ' + (cls || "") + '">' + seg + ticks + '</span>';
}

function zachRow(c) {
  const pct = c.works_total ? Math.round(c.works_passed / c.works_total * 100) : 0;
  const ok = pct >= c.pass_share * 100;
  return '<div class="zach' + (ok ? " ok" : "") + '"><span>✓ Зачтено работ <b>' + c.works_passed + ' из ' + c.works_total + '</b></span>' +
    '<span class="zb"><i style="width:' + pct + '%"></i><em style="left:' + c.pass_share * 100 + '%"></em></span><b>' + pct + '%</b></div>';
}

function sdoNeedConnect(box, text) {
  box.innerHTML = '<div class="card sdo-empty"><div class="big">🎓</div><b>' + escapeHtml(text) + '</b>' +
    '<p class="sheet-hint">Баллы и задания у каждого свои — их видно только со своим входом в СДО.</p>' +
    '<button class="primary" onclick="openSdoSheet()">Подключить СДО</button></div>';
}

function showSdoView(name) {
  sdoView = name;
  switchTab(name);
  window.scrollTo(0, 0);
  if (tg && tg.BackButton) {
    tg.BackButton.offClick(sdoBack);
    if (name !== "sdo") { tg.BackButton.onClick(sdoBack); tg.BackButton.show(); }
  }
}

function sdoBack() {
  haptic();
  if (sdoView === "tk") showSdoView("subject");
  else showSdoView("sdo");
}

// ── Список предметов ──────────────────────────────────────────────────────

async function openSdo(fresh) {
  showSdoView("sdo");
  const box = document.getElementById("sdo-list");
  if (!sdoData || fresh) box.innerHTML = '<div class="skel" style="height:118px"></div><div class="skel" style="height:110px"></div><div class="skel" style="height:110px"></div>';
  else renderSdoList();
  try {
    sdoData = await api("/api/sdo/grades" + (fresh ? "?fresh=1" : ""));
    renderSdoList();
  } catch (e) {
    if (/подключи/.test(e.message)) sdoNeedConnect(box, e.message[0].toUpperCase() + e.message.slice(1));
    else if (!sdoData) box.innerHTML = '<div class="empty">Не загрузилось: ' + escapeHtml(e.message) + '</div>';
  }
}

function renderSdoList() {
  const box = document.getElementById("sdo-list");
  const list = sdoData.courses;
  const ago = Math.max(0, Math.round((Date.now() / 1000 - sdoData.updated) / 60));
  document.getElementById("sdo-updated").textContent = ago < 1 ? "обновлено только что" : "обновлено " + ago + " мин назад";
  if (!list.length) { box.innerHTML = '<div class="empty">В СДО пока нет журналов с баллами за этот семестр</div>'; return; }
  const closed = list.filter(c => c.closed).length;
  const near = list.filter(c => !c.closed).sort((a, b) => a.need - b.need)[0];
  box.innerHTML =
    '<div class="sc-sum"><div class="e">Закрыто на «3» или зачёт</div>' +
      '<div class="b">' + closed + ' из ' + list.length + ' ' + plural(list.length, "предмета", "предметов", "предметов") + '</div>' +
      '<div class="m">' + (near ? "ближе всего: " + escapeHtml(near.title) + " — " + needText(near).replace(/<\/?b>/g, "") : "все предметы закрыты 🎉") + '</div>' +
      '<div class="pips">' + list.map(c => '<i class="' + (c.closed ? "on" : "") + '"></i>').join("") + '</div></div>' +
    '<div class="legend"><span><i style="background:var(--s-tk)"></i>работы</span><span><i style="background:var(--s-pos)"></i>посещения</span><span><i style="background:var(--s-sk)"></i>экзамен/зачёт</span></div>' +
    list.map(c =>
      '<div class="sc-card tap" onclick="openSubject(' + c.id + ')"><div class="sc-top"><div class="t"><span class="sc-kind ' + (c.kind === "credit" ? "za" : "ex") + '">' +
        (c.kind === "credit" ? "ЗАЧ" : "ЭКЗ") + '</span><br>' + escapeHtml(c.title) + '</div>' +
        '<div class="n">' + fmtNum(c.score) + '<span class="of"> / ' + fmtNum(c.max) + '</span></div></div>' +
        scoreBar(c) + '<div class="sc-foot"><span>' + needText(c) + '</span>' + (c.final ? '<span>' + escapeHtml(c.final) + '</span>' : '') + '</div>' +
        (c.works_total ? zachRow(c) : '') + '</div>').join("");
}

// ── Предмет подробно ──────────────────────────────────────────────────────

async function openSubject(id) {
  haptic();
  const base = sdoData && sdoData.courses.find(c => c.id === id);
  sdoCourse = base ? Object.assign({ id: id }, base) : null;
  showSdoView("subject");
  if (sdoCourse) renderSubject();
  else document.getElementById("subject-body").innerHTML = '<div class="skel" style="height:300px"></div>';
  try {
    sdoCourse = await api("/api/sdo/grades/" + id);
    if (sdoView !== "sdo") { renderSubject(); if (sdoView === "tk") renderTk(); }
  } catch (e) {
    if (!base) document.getElementById("subject-body").innerHTML = '<div class="empty">Не загрузилось: ' + escapeHtml(e.message) + '</div>';
  }
}

function renderSubject() {
  const c = sdoCourse;
  const marks = c.marks.map(m => '<span class="gm' + (c.score >= m.at ? " got" : "") + '" style="left:' + (m.at / c.max * 100).toFixed(1) + '%">' +
    '<b>' + (m.label === "зачёт" ? "✓" : escapeHtml(m.label)) + '</b><em>' + (m.label === "зачёт" ? "зачёт · " : "") + m.at + '</em></span>').join("");
  const seg = c.categories.filter(k => k.score > 0)
    .map(k => '<i style="width:' + Math.min(100, k.score / c.max * 100).toFixed(1) + '%;background:' + catColor(k.name) + '"></i>').join("");
  const rows = c.categories.map((k, i) => {
    const go = k.tk && c.works_total;
    return '<div class="cat-row' + (go ? ' go' : '') + '"' + (go ? ' onclick="openTk()"' : '') + '>' +
      '<span class="d" style="background:' + catColor(k.name) + '"></span><span class="nm">' + escapeHtml(k.name) + '</span>' +
      '<span class="mb"><i style="width:' + (k.max ? Math.min(100, k.score / k.max * 100) : 0) + '%;background:' + catColor(k.name) + '"></i></span>' +
      '<span class="v">' + fmtNum(k.score) + '<small>/' + fmtNum(k.max) + '</small></span><span class="chev">' + (go ? '›' : '') + '</span></div>';
  }).join("");
  document.getElementById("subject-body").innerHTML =
    '<h2 class="section" style="margin-top:6px"><span>' + escapeHtml(c.title) + '</span><span class="stat">' + (c.kind === "credit" ? "ЗАЧ" : "ЭКЗ") + '</span></h2>' +
    '<div class="card"><div class="sd-head"><span class="n">' + fmtNum(c.score) + '</span><span class="of">из ' + fmtNum(c.max) + '</span>' +
      '<div class="st">' + (c.final ? escapeHtml(c.final) : (c.kind === "credit" ? "зачёт" : "экзамен")) + '<b' + (c.closed ? ' class="ok"' : '') + '>' + needText(c).replace(/<\/?b>/g, "") + '</b></div></div>' +
      '<div class="gbar"><div class="gtrack">' + seg + '</div>' + marks + '</div>' +
      '<div class="cats">' + rows + '</div>' + (c.works_total ? zachRow(c) : '') + '</div>';
}

// ── Текущий контроль ──────────────────────────────────────────────────────

const WORK_LOOK = {
  ok: ["✓", "зачтено"], low: ["✕", "ниже порога"], wait: ["⏳", "сдано · ждёт оценки"],
  todo: ["📤", "можно сдавать"], offline: ["🏫", "сдаётся на занятии"], soon: ["🔒", "ещё закрыто"],
  miss: ["!", "срок прошёл"], none: ["·", ""],
};

function openTk() {
  haptic();
  tkFilter = "all";
  document.getElementById("tk-back").textContent = "← " + (sdoCourse ? sdoCourse.title : "Предмет");
  showSdoView("tk");
  renderTk();
}

async function refreshTk() {
  if (!sdoCourse) return;
  try {
    sdoCourse = await api("/api/sdo/grades/" + sdoCourse.id);
    if (sdoView === "tk") renderTk();
    if (sdoView === "subject") renderSubject();
  } catch (e) {}
}

// «среда, 15 октября 2026, 23:59» → «15 октября, 23:59»
function shortDate(t) {
  return escapeHtml((t || "").replace(/^[а-яё]+,\s*/i, "").replace(/\s\d{4}(,|$)/, "$1"));
}

function workMeta(w) {
  if (w.status === "soon" && w.opens) return "откроется " + shortDate(w.opens);
  if ((w.status === "todo" || w.status === "miss") && w.due) return "до " + shortDate(w.due) + (w.status === "miss" ? " · срок прошёл" : "");
  return (WORK_LOOK[w.status] || WORK_LOOK.none)[1] || escapeHtml(w.kind);
}

function renderTk() {
  const c = sdoCourse;
  const box = document.getElementById("tk-body");
  if (!c.works || !c.works.length) { box.innerHTML = '<div class="empty">Работ в текущем контроле пока нет</div>'; return; }
  const detailed = !!c.works[0].status;   // страницы заданий уже подгружены
  const works = c.works.map(w => Object.assign({}, w, { status: w.status || (w.grade != null ? (w.passed ? "ok" : "low") : "none") }));
  const tk = c.categories.find(k => k.tk) || { score: works.reduce((a, w) => a + (w.grade || 0), 0), max: works.reduce((a, w) => a + (w.max || 0), 0) };
  const need = Math.ceil(works.length * c.pass_share);
  const passed = works.filter(w => w.status === "ok").length;
  const todo = works.filter(w => w.status === "todo").length;
  const graded = works.filter(w => w.grade != null).length;
  const shown = works.filter(w => tkFilter === "all" || (tkFilter === "todo" ? w.status === "todo" : w.grade != null));
  const sq = s => ({ ok: "g", low: "r", wait: "b" })[s] || "";
  box.innerHTML =
    '<h2 class="section" style="margin-top:6px"><span>Текущий контроль</span><span class="stat">' + escapeHtml(c.title) + '</span></h2>' +
    '<div class="card"><div class="sd-head"><span class="n">' + fmtNum(tk.score) + '</span><span class="of">из ' + fmtNum(tk.max) + '</span>' +
      '<div class="st">зачтено<b' + (passed >= need ? ' class="ok"' : '') + '>' + passed + ' из ' + works.length + ' · нужно ' + need + '</b></div></div>' +
      '<div class="tkbar">' + works.map(w => '<i class="' + sq(w.status) + '"></i>').join("") + '</div>' +
      '<div class="tklegend"><span><i class="g"></i>зачтено</span><span><i class="r"></i>ниже порога</span><span><i class="b"></i>ждёт оценки</span><span><i></i>впереди</span></div></div>' +
    '<div class="chips-row tk-chips">' +
      [["all", "Все · " + works.length], ["todo", "Сдать · " + todo], ["graded", "Оценено · " + graded]]
        .map(([k, t]) => '<button class="' + (tkFilter === k ? "active" : "") + '" onclick="tkFilter=\'' + k + '\'; renderTk()">' + t + '</button>').join("") + '</div>' +
    (detailed ? '' : '<p class="sheet-hint">⏳ Подгружаю сроки и статусы заданий…</p>') +
    '<div class="card pad">' + (shown.length ? shown.map(w => {
      const look = WORK_LOOK[w.status] || WORK_LOOK.none;
      const i = works.indexOf(works.find(x => x.cmid === w.cmid));
      return '<div class="wrow ' + w.status + '" onclick="tapWork(' + i + ')"><span class="wi">' + look[0] + '</span>' +
        '<span class="wn">' + escapeHtml(w.name) + '<small>' + workMeta(w) + '</small></span>' +
        '<span class="ws"><b>' + (w.grade != null ? fmtNum(w.grade) : "—") + '</b>/' + fmtNum(w.max || 0) +
        (w.pass_mark != null ? '<small>зачёт ' + fmtNum(w.pass_mark) + '</small>' : '') + '</span><span class="chev">›</span></div>';
    }).join("") : '<div class="empty">Тут пусто</div>') + '</div>';
}

function tapWork(i) {
  const w = sdoCourse.works[i];
  if (!w) return;
  if (w.can_submit && w.status !== "ok" && w.status !== "wait") {
    openSubmit(0, { cmid: w.cmid, subject: w.name, description: w.url,
      due_text: (sdoCourse.title || "") + (w.due ? " · до " + (w.due || "").replace(/^[а-яё]+,\s*/i, "") : "") });
  } else {
    openLink(w.url);
  }
}
