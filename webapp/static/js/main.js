// Запуск — последним, когда все части уже загружены — часть WebApp (раньше всё жило в одном index.html на 1945 строк).
// Файлы подключаются по порядку и делят глобальную область видимости.

loadToday();
initHomeAdd();
renderChat();
loadChatSubjects();

(function () {
  const q = new URLSearchParams(location.search).get("file");
  const sp = (tg && tg.initDataUnsafe && tg.initDataUnsafe.start_param) || "";
  const id = parseInt(q || (sp.startsWith("file_") ? sp.slice(5) : ""), 10);
  if (id) openFileFromLink(id);
})();
