// Запуск — последним, когда все части уже загружены — часть WebApp (раньше всё жило в одном index.html на 1945 строк).
// Файлы подключаются по порядку и делят глобальную область видимости.

loadToday();
initHomeAdd();
initOptional();
renderChat();
loadChatSubjects();

(function () {
  const q = new URLSearchParams(location.search).get("file");
  const sp = (tg && tg.initDataUnsafe && tg.initDataUnsafe.start_param) || "";
  const id = parseInt(q || (sp.startsWith("file_") ? sp.slice(5) : ""), 10);
  if (id) openFileFromLink(id);
})();

// Кнопка из уведомления бота открывает приложение сразу на нужном экране:
// ?tab=deadlines / files / chat / sdo / search / notify («Корнилов», keyboards.app_button).
(function () {
  const tab = new URLSearchParams(location.search).get("tab");
  const deepLink = tab || new URLSearchParams(location.search).get("file");
  if (!deepLink) maybeOnboard();      // из уведомления — сразу к делу, знакомство потом
  if (tab === "sdo") openSdo();
  else if (tab === "notify") openNotify();
  else if (["deadlines", "files", "chat", "search"].includes(tab)) switchTab(tab);
})();
