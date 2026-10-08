// Файлы курсов: предметы → файлы по типам (лекции, практики…). Нажал файл —
// лист: конспект (общий на всех, ИИ зовётся один раз), скачать, прислать в Telegram.
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/tg_html.dart';

class FileItem {
  final int id;
  final String title, subject, fileName, category;
  final bool hasText, hasSummary;

  FileItem.fromJson(Map<String, dynamic> j)
    : id = j['id'] as int,
      title = j['title'] ?? '',
      subject = j['subject'] ?? '',
      fileName = j['file_name'] ?? '',
      category = j['category'] ?? 'other',
      hasText = j['has_text'] == true,
      hasSummary = j['has_summary'] == true;
}

/// Подписи типов — без эмодзи (в интерфейсе их не используем).
const categoryLabels = {
  'lecture': 'Лекции',
  'practice': 'Практики и лабы',
  'control': 'КР и тесты',
  'method': 'Методички',
  'exam': 'Экзамен и зачёт',
  'other': 'Другое',
};

const _categoryIcons = {
  'lecture': Icons.menu_book_outlined,
  'practice': Icons.science_outlined,
  'control': Icons.fact_check_outlined,
  'method': Icons.library_books_outlined,
  'exam': Icons.workspace_premium_outlined,
  'other': Icons.insert_drive_file_outlined,
};

class FilesScreen extends StatelessWidget {
  final Api api;
  const FilesScreen({super.key, required this.api});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          child: Loader<List<FileItem>>(
            load: () async => [for (final f in (await api.get('/files'))['items'] as List) FileItem.fromJson(f)],
            builder: (context, files, _) {
              final bySubject = <String, List<FileItem>>{};
              for (final f in files) {
                (bySubject[f.subject.isEmpty ? 'Без предмета' : f.subject] ??= []).add(f);
              }
              final subjects = bySubject.keys.toList()..sort();
              return ListView(
                padding: const EdgeInsets.only(bottom: Space.xxl),
                children: [
                  const BackRow(),
                  ScreenTitle(eyebrow: '${files.length} ${_files(files.length)} группы', title: 'Файлы'),
                  if (files.isEmpty)
                    const Notice(title: 'Пока пусто', text: 'Файлы курсов появятся после выгрузки из СДО.'),
                  for (final s in subjects)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                      child: _SubjectRow(
                        subject: s,
                        count: bySubject[s]!.length,
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => SubjectFilesScreen(api: api, subject: s, files: bySubject[s]!),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

String _files(int n) => plural(n, 'файл', 'файла', 'файлов');

/// Кнопка «назад» вверху экранов, открытых поверх вкладок.
class BackRow extends StatelessWidget {
  const BackRow({super.key});

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Padding(
      padding: const EdgeInsets.only(left: Space.s),
      child: IconButton(
        tooltip: 'Назад',
        onPressed: () => Navigator.pop(context),
        icon: Icon(Icons.arrow_back_ios_new_rounded, size: 20, color: AppStyle.of(context).p.text),
      ),
    ),
  );
}

class _SubjectRow extends StatelessWidget {
  final String subject;
  final int count;
  final VoidCallback onTap;
  const _SubjectRow({required this.subject, required this.count, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    return Tile(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: subjectColor(subject), shape: BoxShape.circle),
          ),
          const SizedBox(width: Space.m),
          Expanded(
            child: Text(subject, style: s.body(15, weight: FontWeight.w600)),
          ),
          Text('$count', style: s.body(14, color: s.p.muted)),
          Icon(Icons.chevron_right_rounded, color: s.p.muted),
        ],
      ),
    );
  }
}

class SubjectFilesScreen extends StatelessWidget {
  final Api api;
  final String subject;
  final List<FileItem> files;
  const SubjectFilesScreen({super.key, required this.api, required this.subject, required this.files});

  @override
  Widget build(BuildContext context) {
    final byCat = <String, List<FileItem>>{};
    for (final f in files) {
      (byCat[f.category] ??= []).add(f);
    }
    final p = AppStyle.of(context).p;
    return Scaffold(
      body: Backdrop(
        tint: subjectColor(subject),
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: Space.xxl),
            children: [
              const BackRow(),
              ScreenTitle(eyebrow: '${files.length} ${_files(files.length)}', title: subject),
              for (final cat in categoryLabels.keys)
                if (byCat[cat] != null) ...[
                  Section(categoryLabels[cat]!),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.l),
                    child: Tile(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < byCat[cat]!.length; i++) ...[
                            if (i > 0) Divider(height: 1, color: p.line),
                            _FileRow(api: api, f: byCat[cat]![i]),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  final Api api;
  final FileItem f;
  const _FileRow({required this.api, required this.f});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final ext = f.fileName.contains('.') ? f.fileName.split('.').last.toUpperCase() : '';
    return InkWell(
      onTap: () {
        tick();
        showFileSheet(context, api, f);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
        child: Row(
          children: [
            Icon(_categoryIcons[f.category] ?? Icons.insert_drive_file_outlined, color: s.p.muted, size: 20),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.title, style: s.body(15, weight: FontWeight.w600)),
                  if (ext.isNotEmpty || f.hasSummary)
                    Text(
                      [if (ext.isNotEmpty) ext, if (f.hasSummary) 'есть конспект'].join(' · '),
                      style: s.body(12, color: s.p.muted),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> showFileSheet(BuildContext context, Api api, FileItem f) {
  final s = AppStyle.of(context);
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: s.p.cardSolid,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _FileSheet(api: api, f: f),
  );
}

class _FileSheet extends StatefulWidget {
  final Api api;
  final FileItem f;
  const _FileSheet({required this.api, required this.f});

  @override
  State<_FileSheet> createState() => _FileSheetState();
}

class _FileSheetState extends State<_FileSheet> {
  String? _summary, _note;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.f.hasSummary) _loadSummary(make: false);
  }

  Future<void> _loadSummary({required bool make}) async {
    setState(() {
      _busy = true;
      _note = make ? 'Делаю конспект — это до минуты…' : null;
    });
    try {
      final r = make
          ? await widget.api.post('/summary/${widget.f.id}')
          : await widget.api.get('/summary/${widget.f.id}');
      setState(() {
        _summary = r['summary'] as String?;
        _note = null;
      });
    } on ApiError catch (e) {
      setState(() => _note = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _download() async {
    tick();
    try {
      final r = await widget.api.post('/files/${widget.f.id}/link');
      await launchUrl(Uri.parse(r['url'] as String), mode: LaunchMode.externalApplication);
    } on ApiError catch (e) {
      // Больше 20 МБ Bot API не отдаёт — тогда файл придёт в Telegram.
      setState(() => _note = e.message);
      await _send();
    }
  }

  Future<void> _send() async {
    tick();
    try {
      await widget.api.post('/files/${widget.f.id}/send');
      setState(() => _note = 'Отправил в Telegram — файл в чате с ботом.');
    } on ApiError catch (e) {
      setState(() => _note = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.f.subject, style: s.eyebrow()),
              const SizedBox(height: 4),
              Text(widget.f.title, style: s.title(24)),
              const SizedBox(height: Space.l),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: p.accent,
                        foregroundColor: p.onAccent,
                        shape: const StadiumBorder(),
                      ),
                      onPressed: _download,
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Скачать'),
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.text,
                        side: BorderSide(color: p.line),
                        shape: const StadiumBorder(),
                      ),
                      onPressed: _send,
                      icon: const Icon(Icons.send_rounded, size: 18),
                      label: const Text('В Telegram'),
                    ),
                  ),
                ],
              ),
              if (_note != null) ...[const SizedBox(height: Space.m), Text(_note!, style: s.body(14, color: p.muted))],
              if (widget.f.hasText) ...[
                const SizedBox(height: Space.xl),
                Text('Конспект', style: s.title(20)),
                const SizedBox(height: Space.s),
                if (_summary != null)
                  Text.rich(tgHtml(_summary!, s.body(15), link: p.accent, codeBg: p.line))
                else if (_busy)
                  Padding(
                    padding: const EdgeInsets.all(Space.l),
                    child: Center(child: CircularProgressIndicator(color: p.accent, strokeWidth: 2.5)),
                  )
                else
                  TextButton.icon(
                    onPressed: () => _loadSummary(make: true),
                    icon: Icon(Icons.auto_awesome_outlined, color: p.accent),
                    label: Text(
                      'Сделать конспект',
                      style: s.body(15, weight: FontWeight.w600, color: p.accent),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
