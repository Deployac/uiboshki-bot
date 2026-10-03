// Сайт-презентация (/about): масштаб телефона, появление блоков и живой
// поиск расписания МИРЭА (/about/api/search, /about/api/target).
(function () {
  "use strict";
  const $ = (id) => document.getElementById(id);
  const esc = (s) => String(s == null ? "" : s).replace(/[&<>"']/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);

  // приложение рисуется в настоящем размере телефона (390×844) и ужимается под рамку
  const phone = $("phone");
  function fit() {
    const screen = phone.querySelector(".phone-screen");
    phone.style.setProperty("--scale", (screen.clientWidth / 390).toFixed(4));
  }
  fit();
  window.addEventListener("resize", fit);

  // блоки проявляются один раз, когда доходят до экрана
  const io = "IntersectionObserver" in window ? new IntersectionObserver((entries) => {
    entries.forEach((e) => { if (e.isIntersecting) { e.target.classList.add("in"); io.unobserve(e.target); } });
  }, { rootMargin: "0px 0px -8% 0px" }) : null;
  document.querySelectorAll(".reveal").forEach((el) => (io ? io.observe(el) : el.classList.add("in")));

  // ── поиск расписания ──
  const TYPE = { 1: "группа", 2: "преподаватель", 3: "аудитория" };
  const DAYS = ["Понедельник", "Вторник", "Среда", "Четверг", "Пятница", "Суббота", "Воскресенье"];
  const MONTHS = ["января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября", "октября", "ноября", "декабря"];
  const q = $("q"), results = $("results"), week = $("week");
  let timer = null, seq = 0, target = null, weekIdx = 0;

  async function getJSON(url) {
    const r = await fetch(url);
    if (r.status === 429) throw new Error("Слишком часто — подожди минуту.");
    if (!r.ok) throw new Error("Сайт МИРЭА сейчас не отвечает — попробуй чуть позже.");
    return r.json();
  }

  q.addEventListener("input", () => {
    clearTimeout(timer);
    timer = setTimeout(search, 250);
  });

  async function search() {
    const text = q.value.trim();
    const my = ++seq;
    if (text.length < 2) { results.innerHTML = ""; return; }
    try {
      const data = await getJSON("/about/api/search?q=" + encodeURIComponent(text));
      if (my !== seq) return;                       // уже напечатали дальше
      const items = (data.items || []).slice(0, 8);
      results.innerHTML = items.length
        ? items.map((it, i) => '<button type="button" data-i="' + i + '">' + esc(it.title) +
            '<small>' + esc(it.hint || TYPE[it.type] || "") + '</small></button>').join("")
        : '<div class="hint">Ничего не нашлось — попробуй иначе: «УИБО-03», фамилия, «А-17»</div>';
      results.querySelectorAll("button").forEach((b) => b.addEventListener("click", () => open(items[+b.dataset.i], b)));
    } catch (e) {
      if (my === seq) results.innerHTML = '<div class="hint">' + esc(e.message) + '</div>';
    }
  }

  async function open(it, btn) {
    results.querySelectorAll("button").forEach((b) => b.classList.toggle("on", b === btn));
    const my = ++seq;
    week.innerHTML = '<div class="err">Загружаю расписание…</div>';
    try {
      const data = await getJSON("/about/api/target/" + it.type + "/" + it.id);
      if (my !== seq) return;
      target = data; weekIdx = 0;
      renderWeek();
    } catch (e) {
      if (my === seq) week.innerHTML = '<div class="err">' + esc(e.message) + '</div>';
    }
  }

  function dayLabel(iso) {
    const d = new Date(iso + "T12:00:00");
    return { name: DAYS[(d.getDay() + 6) % 7], date: d.getDate() + " " + MONTHS[d.getMonth()] };
  }

  function renderWeek() {
    const w = target.weeks[weekIdx];
    if (!w) return;
    const tabs = target.weeks.map((x, i) =>
      '<button type="button" data-w="' + i + '" class="' + (i === weekIdx ? "on" : "") + '">' +
      (i === 0 ? "Эта неделя" : "Следующая") + '</button>').join("");
    const days = w.days.filter((d, i) => i < 6 || d.lessons.length).map((d) => {
      const lbl = dayLabel(d.date);
      const rows = d.lessons.map((l) =>
        '<div class="ls' + (l.status === "now" ? " now" : "") + '"><time>' + esc(l.start) + '–' + esc(l.end) + '</time>' +
        '<div><b>' + esc(l.title) + '</b><span>' + esc([l.kind, l.room, target.type === 2 ? l.groups : l.teacher].filter(Boolean).join(" · ")) +
        '</span></div></div>').join("");
      return '<div class="day' + (d.date === target.today ? " today" : "") + (d.lessons.length ? "" : " empty") + '">' +
        '<div class="day-name">' + lbl.name + '<small>' + lbl.date + (d.date === target.today ? " · сегодня" : "") + '</small></div>' +
        '<div class="lessons">' + (rows || "свободно") + '</div></div>';
    }).join("");
    week.innerHTML = '<div class="week-top"><h3>' + esc(target.title) + (w.week ? ' <small style="font-size:15px;color:var(--muted)">· ' + w.week + ' неделя</small>' : '') +
      '</h3><div class="tabs">' + tabs + '</div></div>' + days;
    week.querySelectorAll(".tabs button").forEach((b) => b.addEventListener("click", () => { weekIdx = +b.dataset.w; renderWeek(); }));
  }
})();
