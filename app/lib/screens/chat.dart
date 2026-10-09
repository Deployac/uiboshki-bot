// Помощник: вопросы ИИ, который опирается на лекции группы. Можно выбрать
// предмет; под ответом — откуда взято («Лекция 4 · стр. 3»), нажал — страница.
// Вложение (фото или PDF/DOCX/PPTX/TXT до 10 МБ) уходит ИИ один раз, а текст
// документа (file_text с сервера) помнится в вопросе — следующие вопросы знают
// файл. История — на телефоне (последние 40 сообщений), «Новый чат» — с нуля.
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/tg_html.dart';
import 'files.dart';

class ChatMsg {
  final String role, content, html;
  final List<Map<String, dynamic>> sources, files;
  final List<String> choose;
  final bool error;

  /// Вложение вопроса: имя и фото ли (сами байты не храним).
  final ({String name, bool image})? att;

  /// Текст вложенного документа — уходит в историю следующих вопросов.
  String fileText;

  /// Вопрос без ответа (ошибка) — в историю не идёт, иначе ИИ отвечал на него позже.
  bool failed;

  ChatMsg(
    this.role,
    this.content, {
    this.html = '',
    this.sources = const [],
    this.files = const [],
    this.choose = const [],
    this.error = false,
    this.att,
    this.fileText = '',
    this.failed = false,
  });

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    if (html.isNotEmpty) 'html': html,
    if (sources.isNotEmpty) 'sources': sources,
    if (files.isNotEmpty) 'files': files,
    if (att != null) 'att': {'name': att!.name, 'image': att!.image},
    if (fileText.isNotEmpty) 'file_text': fileText,
    if (failed) 'failed': true,
  };

  factory ChatMsg.fromJson(Map<String, dynamic> j) {
    final a = j['att'];
    return ChatMsg(
      j['role'] ?? 'user',
      j['content'] ?? '',
      html: j['html'] ?? '',
      sources: [for (final s in (j['sources'] as List? ?? [])) Map<String, dynamic>.from(s)],
      files: [for (final f in (j['files'] as List? ?? [])) Map<String, dynamic>.from(f)],
      att: a is Map ? (name: '${a['name'] ?? 'файл'}', image: a['image'] == true) : null,
      fileText: j['file_text'] ?? '',
      failed: j['failed'] == true,
    );
  }
}

/// Вложение, которое ещё не ушло.
class ChatAttachment {
  final String name, mime;
  final Uint8List bytes;
  const ChatAttachment(this.name, this.mime, this.bytes);
  bool get image => mime.startsWith('image/');
}

/// Выбор вложения — системным окном; в тестах подменяется.
typedef PickAttachment = Future<ChatAttachment?> Function();

const maxAttachmentBytes = 10 * 1024 * 1024;

const _mimes = {
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'png': 'image/png',
  'webp': 'image/webp',
  'heic': 'image/heic',
  'pdf': 'application/pdf',
  'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  'txt': 'text/plain',
};

String mimeOf(String name) => _mimes[name.split('.').last.toLowerCase()] ?? '';

Future<ChatAttachment?> systemPickAttachment() async {
  final files = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: _mimes.keys.toList());
  if (files.isEmpty) return null;
  final f = files.first;
  return ChatAttachment(f.name, mimeOf(f.name), await f.xFile.readAsBytes());
}

/// История чата на телефоне. Ключ — с приставкой кэша API: «выйти» стирает и её.
const chatStoreKey = 'uib_cache:chat';
const chatKeep = 40;

class ChatScreen extends StatefulWidget {
  final Api api;
  final PickAttachment pick;
  const ChatScreen({super.key, required this.api, this.pick = systemPickAttachment});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _log = <ChatMsg>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  String _subject = '';
  List<String> _subjects = [];
  bool _waiting = false;
  ChatAttachment? _att;
  String? _attNote; // «больше 10 МБ» и т. п.
  int _chat = 0; // номер разговора: ответ на вопрос из прошлого чата не попадёт в новый

  @override
  void initState() {
    super.initState();
    _restore();
    widget.api
        .get('/subjects')
        .then((j) {
          if (!mounted) return;
          setState(
            () => _subjects = [
              for (final s in j['subjects'] as List)
                if (s['lectures'] == true) s['name'] as String,
            ],
          );
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _restore() async {
    try {
      final raw = (await SharedPreferences.getInstance()).getString(chatStoreKey);
      if (raw == null || !mounted || _log.isNotEmpty) return;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _log.addAll([for (final m in j['log'] as List) ChatMsg.fromJson(Map<String, dynamic>.from(m))]);
        _subject = j['subject'] ?? '';
      });
      _toEnd();
    } catch (_) {}
  }

  /// Ошибки и «по какому предмету?» не храним — это не разговор.
  Future<void> _save() async {
    final keep = [
      for (final m in _log)
        if (!m.error && m.choose.isEmpty) m.toJson(),
    ];
    try {
      final prefs = await SharedPreferences.getInstance();
      if (keep.isEmpty) {
        await prefs.remove(chatStoreKey);
      } else {
        final tail = keep.length > chatKeep ? keep.sublist(keep.length - chatKeep) : keep;
        await prefs.setString(chatStoreKey, jsonEncode({'log': tail, 'subject': _subject}));
      }
    } catch (_) {}
  }

  void _newChat() {
    tick();
    setState(() {
      _chat++;
      _log.clear();
      _att = null;
      _attNote = null;
      _waiting = false;
      _input.clear();
    });
    _save();
  }

  Future<void> _attach() async {
    tick();
    final ChatAttachment? a;
    try {
      a = await widget.pick();
    } catch (_) {
      return;
    }
    if (a == null || !mounted) return;
    setState(() {
      if (a!.bytes.length > maxAttachmentBytes) {
        _att = null;
        _attNote = 'Файл больше 10 МБ — не пролезет.';
      } else if (a.mime.isEmpty) {
        _att = null;
        _attNote = 'Умею читать PDF, DOCX, PPTX и TXT, а ещё фото.';
      } else {
        _att = a;
        _attNote = null;
      }
    });
  }

  Future<void> _send({String? again, ChatAttachment? againAtt}) async {
    final text = again ?? _input.text.trim();
    final att = again != null ? againAtt : _att;
    if ((text.isEmpty && att == null) || _waiting) return;
    tick();
    final chat = _chat;
    ChatMsg entry;
    if (again == null) {
      // В истории — только текст; само вложение уходит отдельным полем.
      entry = ChatMsg(
        'user',
        text.isNotEmpty ? text : (att!.image ? 'Реши задание на фото.' : 'Разбери этот файл.'),
        att: att == null ? null : (name: att.name, image: att.image),
      );
      _log.add(entry);
    } else {
      entry = _log.lastWhere((m) => m.role == 'user');
    }
    setState(() {
      entry.failed = false;
      _input.clear();
      _att = null;
      _attNote = null;
      _waiting = true;
    });
    _toEnd();
    final history = [
      for (final m in _log)
        if (!m.error && !m.failed && m.content.isNotEmpty && m.choose.isEmpty)
          {'role': m.role, 'content': m.fileText.isEmpty ? m.content : '${m.content}\n\n${m.fileText}'},
    ];
    final body = <String, dynamic>{'history': history, 'subject': _subject};
    if (att != null) body['attachment'] = {'name': att.name, 'mime': att.mime, 'data': base64Encode(att.bytes)};
    ChatMsg answer;
    try {
      final r = await widget.api.post('/chat', body);
      if (r['file_text'] is String) entry.fileText = r['file_text'];
      final choose = [for (final c in (r['choose'] as List? ?? [])) '$c'];
      answer = ChatMsg(
        'assistant',
        r['content'] ?? '',
        html: r['html'] ?? '',
        sources: [for (final s in (r['sources'] as List? ?? [])) Map<String, dynamic>.from(s)],
        files: [for (final f in (r['files'] as List? ?? [])) Map<String, dynamic>.from(f)],
        choose: choose,
      );
      if (choose.isNotEmpty) _chooseAtt = att; // выберет предмет — вложение уйдёт ещё раз
    } on ApiError catch (e) {
      entry.failed = true;
      answer = ChatMsg('assistant', e.message, error: true);
    } catch (e) {
      entry.failed = true;
      answer = ChatMsg('assistant', errorText(e), error: true);
    }
    if (!mounted || chat != _chat) return; // пока ждали, начали новый чат
    setState(() {
      _log.add(answer);
      _waiting = false;
    });
    _save();
    _toEnd();
  }

  ChatAttachment? _chooseAtt;

  void _toEnd() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scroll.hasClients) {
      _scroll.animateTo(
        _scroll.position.maxScrollExtent + 200,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }
  });

  Future<void> _pickSubject() async {
    final s = AppStyle.of(context);
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: s.p.cardSolid,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final name in ['', ..._subjects])
                ListTile(
                  title: Text(name.isEmpty ? 'Все предметы' : name, style: s.body(15)),
                  trailing: name == _subject ? Icon(Icons.check_rounded, color: s.p.accent) : null,
                  onTap: () => Navigator.pop(ctx, name),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked != null) setState(() => _subject = picked);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          child: Column(
            children: [
              Row(
                children: [
                  const BackRow(),
                  const Spacer(),
                  if (_log.isNotEmpty)
                    IconButton(
                      tooltip: 'Новый чат',
                      onPressed: _newChat,
                      icon: Icon(Icons.add_comment_outlined, color: p.text),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: Space.l),
                    child: ActionChip(
                      onPressed: _pickSubject,
                      backgroundColor: p.card,
                      side: BorderSide(color: p.line),
                      shape: const StadiumBorder(),
                      avatar: Icon(Icons.menu_book_outlined, size: 16, color: p.accent),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 170),
                        child: Text(
                          _subject.isEmpty ? 'Все предметы' : _subject,
                          overflow: TextOverflow.ellipsis,
                          style: s.body(13, weight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              Expanded(
                child: ListView(
                  controller: _scroll,
                  padding: const EdgeInsets.only(bottom: Space.l),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  children: [
                    const ScreenTitle(title: 'Помощник'),
                    if (_log.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                        child: Wrap(
                          spacing: Space.s,
                          runSpacing: Space.s,
                          children: [
                            for (final q in const [
                              'Чем метрика отличается от KPI?',
                              'Объясни 3 лекцию',
                              'Что сдать на этой неделе?',
                            ])
                              ActionChip(
                                backgroundColor: p.card,
                                side: BorderSide(color: p.line),
                                shape: const StadiumBorder(),
                                // у чипа текст в одну строку и обрезается молча — переносим
                                label: Text(q, softWrap: true, maxLines: 3, style: s.body(13)),
                                onPressed: () {
                                  _input.text = q;
                                  _send();
                                },
                              ),
                          ],
                        ),
                      ),
                    for (final m in _log)
                      _Bubble(
                        m: m,
                        api: widget.api,
                        onChoose: (subj) {
                          setState(() => _subject = subj);
                          final lastQ = _log.lastWhere((x) => x.role == 'user');
                          _send(again: lastQ.content, againAtt: _chooseAtt);
                        },
                      ),
                    if (_waiting)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, 0),
                        child: Text('Думаю…', style: s.eyebrow()),
                      ),
                  ],
                ),
              ),
              if (_att != null || _attNote != null)
                _AttachPreview(
                  att: _att,
                  note: _attNote,
                  onClear: () => setState(() {
                    _att = null;
                    _attNote = null;
                  }),
                ),
              _InputBar(controller: _input, busy: _waiting, onSend: _send, onAttach: _attach),
            ],
          ),
        ),
      ),
    );
  }
}

/// «Прикреплено: имя» над полем ввода, с крестиком.
class _AttachPreview extends StatelessWidget {
  final ChatAttachment? att;
  final String? note;
  final VoidCallback onClear;
  const _AttachPreview({required this.att, required this.note, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final a = att;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
      child: Container(
        padding: const EdgeInsets.only(left: Space.m),
        decoration: BoxDecoration(
          color: p.card,
          borderRadius: BorderRadius.circular(Radii.chip),
          border: Border.all(color: a == null ? p.danger : p.line),
        ),
        child: Row(
          children: [
            Icon(
              a == null ? Icons.error_outline_rounded : (a.image ? Icons.image_outlined : Icons.description_outlined),
              size: 18,
              color: a == null ? p.danger : p.accent,
            ),
            const SizedBox(width: Space.s),
            Expanded(
              child: Text(
                a == null ? note! : 'прикреплено: ${a.name}',
                overflow: TextOverflow.ellipsis,
                style: s.body(13, color: a == null ? p.danger : p.text),
              ),
            ),
            IconButton(
              tooltip: 'Убрать',
              onPressed: onClear,
              icon: Icon(Icons.close_rounded, size: 18, color: p.muted),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMsg m;
  final Api api;
  final ValueChanged<String> onChoose;
  const _Bubble({required this.m, required this.api, required this.onChoose});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    if (m.role == 'user') {
      final a = m.att;
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.8),
          margin: const EdgeInsets.fromLTRB(Space.xxl, Space.s, Space.l, Space.s),
          padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
          decoration: BoxDecoration(
            color: p.accent,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(Radii.tile),
              topRight: Radius.circular(Radii.tile),
              bottomLeft: Radius.circular(Radii.tile),
              bottomRight: Radius.circular(6),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (a != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(a.image ? Icons.image_outlined : Icons.description_outlined, size: 16, color: p.onAccent),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          a.name,
                          overflow: TextOverflow.ellipsis,
                          style: s.body(13, weight: FontWeight.w600, color: p.onAccent),
                        ),
                      ),
                    ],
                  ),
                ),
              Text(m.content, style: s.body(15, color: p.onAccent)),
            ],
          ),
        ),
      );
    }
    final body = s.body(15, color: m.error ? p.danger : p.text);
    // поиск по смыслу: «Лекция 5 · слайд 12» → страница; одинаковые места — один чип
    final seen = <String>{};
    final pages = [
      for (final src in m.sources)
        if (src['page'] != null && seen.add('${src['id']}:${src['page']}')) src,
    ];
    final whole = [
      for (final src in m.sources)
        if (src['page'] == null) src,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.s, Space.xl, Space.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectionArea(
            child: m.html.isNotEmpty
                ? Text.rich(tgHtml(m.html, body, link: p.accent, codeBg: p.line))
                : Text(m.content, style: body),
          ),
          if (m.choose.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final c in m.choose)
                  ActionChip(
                    backgroundColor: p.card,
                    side: BorderSide(color: p.accent),
                    shape: const StadiumBorder(),
                    // длинное название предмета — в две строки, а не обрезано
                    label: Text(c, softWrap: true, maxLines: 3, style: s.body(13, weight: FontWeight.w600)),
                    onPressed: () {
                      tick();
                      onChoose(c);
                    },
                  ),
              ],
            ),
          ],
          // «скинь лк 5 по …» — найденные файлы, нажал — лист файла
          if (m.files.isNotEmpty || pages.isNotEmpty || whole.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final f in m.files)
                  _chip(
                    context,
                    icon: Icons.insert_drive_file_outlined,
                    label: '${f['title']}',
                    onTap: () => showFileSheet(context, api, FileItem.fromJson(f)),
                  ),
                for (final src in pages.take(6))
                  _chip(
                    context,
                    icon: Icons.auto_stories_outlined,
                    label: '${src['label'] ?? src['title']}',
                    onTap: () => showPageSheet(context, api, src['id'] as int, (src['page'] as num).toInt()),
                  ),
                for (final src in whole.take(4))
                  _chip(
                    context,
                    icon: Icons.menu_book_outlined,
                    label: '${src['title']}',
                    onTap: () => showFileSheet(
                      context,
                      api,
                      FileItem.fromJson({'id': src['id'], 'title': src['title'], 'has_text': true}),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, {required IconData icon, required String label, required VoidCallback onTap}) {
    final s = AppStyle.of(context);
    final p = s.p;
    return ActionChip(
      backgroundColor: p.card,
      side: BorderSide(color: p.line),
      shape: const StadiumBorder(),
      avatar: Icon(icon, size: 16, color: p.accent),
      label: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: s.body(12, color: p.muted),
      ),
      onPressed: () {
        tick();
        onTap();
      },
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend, onAttach;
  const _InputBar({required this.controller, required this.busy, required this.onSend, required this.onAttach});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: p.tabbar,
          borderRadius: BorderRadius.circular(Radii.tabbar),
          border: Border.all(color: p.line),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Прикрепить фото или файл',
              onPressed: busy ? null : onAttach,
              icon: Icon(Icons.attach_file_rounded, color: p.muted),
            ),
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 5,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
                style: s.body(15),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  hintText: 'Спроси про лекцию или задачу',
                  hintStyle: s.body(15, color: p.muted),
                ),
              ),
            ),
            IconButton.filled(
              tooltip: 'Отправить',
              style: IconButton.styleFrom(backgroundColor: p.accent, foregroundColor: p.onAccent),
              onPressed: busy ? null : onSend,
              icon: const Icon(Icons.arrow_upward_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
