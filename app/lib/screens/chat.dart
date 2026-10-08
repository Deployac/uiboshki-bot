// Помощник: вопросы ИИ, который опирается на лекции группы. Можно выбрать
// предмет; под ответом — откуда взято («Лекция 4 · стр. 3»), нажал — файл.
import 'package:flutter/material.dart';

import '../api/api.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/tg_html.dart';
import 'files.dart';

class ChatMsg {
  final String role, content, html;
  final List<Map<String, dynamic>> sources;
  final List<String> choose;
  final bool error;
  ChatMsg(
    this.role,
    this.content, {
    this.html = '',
    this.sources = const [],
    this.choose = const [],
    this.error = false,
  });
}

class ChatScreen extends StatefulWidget {
  final Api api;
  const ChatScreen({super.key, required this.api});

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

  @override
  void initState() {
    super.initState();
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

  Future<void> _send([String? again]) async {
    final text = again ?? _input.text.trim();
    if (text.isEmpty || _waiting) return;
    tick();
    setState(() {
      if (again == null) _log.add(ChatMsg('user', text));
      _input.clear();
      _waiting = true;
    });
    _toEnd();
    final history = [
      for (final m in _log)
        if (!m.error && m.content.isNotEmpty && m.choose.isEmpty) {'role': m.role, 'content': m.content},
    ];
    try {
      final r = await widget.api.post('/chat', {'history': history, 'subject': _subject});
      setState(
        () => _log.add(
          ChatMsg(
            'assistant',
            r['content'] ?? '',
            html: r['html'] ?? '',
            sources: [for (final s in (r['sources'] as List? ?? [])) Map<String, dynamic>.from(s)],
            choose: [for (final c in (r['choose'] as List? ?? [])) '$c'],
          ),
        ),
      );
    } on ApiError catch (e) {
      setState(() => _log.add(ChatMsg('assistant', e.message, error: true)));
    } catch (_) {
      setState(() => _log.add(ChatMsg('assistant', 'Нет связи с сервером — попробуй ещё раз.', error: true)));
    } finally {
      if (mounted) setState(() => _waiting = false);
      _toEnd();
    }
  }

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
                  Padding(
                    padding: const EdgeInsets.only(right: Space.l),
                    child: ActionChip(
                      onPressed: _pickSubject,
                      backgroundColor: p.card,
                      side: BorderSide(color: p.line),
                      shape: const StadiumBorder(),
                      avatar: Icon(Icons.menu_book_outlined, size: 16, color: p.accent),
                      label: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
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
                  children: [
                    const ScreenTitle(eyebrow: 'отвечает по лекциям группы', title: 'Помощник'),
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
                                label: Text(q, style: s.body(13)),
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
                          _send(lastQ.content);
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
              _InputBar(controller: _input, busy: _waiting, onSend: _send),
            ],
          ),
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
          child: Text(m.content, style: s.body(15, color: p.onAccent)),
        ),
      );
    }
    final body = s.body(15, color: m.error ? p.danger : p.text);
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
                    label: Text(c, style: s.body(13, weight: FontWeight.w600)),
                    onPressed: () {
                      tick();
                      onChoose(c);
                    },
                  ),
              ],
            ),
          ],
          if (m.sources.isNotEmpty) ...[
            const SizedBox(height: Space.s),
            Wrap(
              spacing: Space.s,
              runSpacing: Space.s,
              children: [
                for (final src in m.sources)
                  ActionChip(
                    backgroundColor: p.card,
                    side: BorderSide(color: p.line),
                    shape: const StadiumBorder(),
                    avatar: Text(
                      '${src['n']}',
                      style: s.body(12, weight: FontWeight.w700, color: p.accent),
                    ),
                    label: Text('${src['label']}', style: s.body(12, color: p.muted)),
                    onPressed: () => showFileSheet(
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
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool busy;
  final VoidCallback onSend;
  const _InputBar({required this.controller, required this.busy, required this.onSend});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.m),
      child: Container(
        padding: const EdgeInsets.only(left: Space.l, right: 6),
        decoration: BoxDecoration(
          color: p.tabbar,
          borderRadius: BorderRadius.circular(Radii.tabbar),
          border: Border.all(color: p.line),
        ),
        child: Row(
          children: [
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
