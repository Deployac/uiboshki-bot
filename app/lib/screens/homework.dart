// ДЗ группы (доска старосты, /addhw в боте) и заметки к парам на сегодня
// и завтра (/note в боте) — входы плитками на вкладке «Сдать».
import 'package:flutter/material.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/capy.dart';
import '../widgets/common.dart';
import 'deadline_edit.dart' show snack;
import 'files.dart' show BackRow;

class Homework {
  final int id;
  final String subject, content, lessonDate;
  final bool hasFile;

  Homework.fromJson(Map<String, dynamic> j)
    : id = j['id'] as int,
      subject = j['subject'] as String? ?? '',
      content = j['content'] as String? ?? '',
      lessonDate = j['lesson_date'] as String? ?? '',
      hasFile = j['has_file'] == true;
}

/// «пт, 9 окт» — везде на доске ДЗ и в заметках один формат (владелец, 2.14).
String shortDay(String isoDate) {
  final d = DateTime.tryParse(isoDate);
  if (d == null) return isoDate;
  return '${weekdaysShort[d.weekday - 1].toLowerCase()}, ${d.day} ${monthsShort[d.month - 1]}';
}

/// Задание к прошедшей паре (срок раньше сегодня) — вниз, под «Прошло».
bool homeworkPast(Homework h, DateTime today) {
  final d = DateTime.tryParse(h.lessonDate);
  return d != null && d.isBefore(DateTime(today.year, today.month, today.day));
}

/// Экран поверх вкладок: фон, «назад», загрузка.
class _Page<T> extends StatelessWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext, T) builder;
  const _Page({super.key, required this.load, required this.builder});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Backdrop(
      child: SafeArea(
        child: Loader<T>(load: load, builder: (context, data, _) => builder(context, data)),
      ),
    ),
  );
}

class HomeworkScreen extends StatelessWidget {
  final Api api;
  const HomeworkScreen({super.key, required this.api});

  Future<void> _send(BuildContext context, Homework h) async {
    tick();
    try {
      await api.post('/homework/${h.id}/send');
      if (context.mounted) snack(context, 'Отправил в Telegram — файл в чате с ботом.');
    } on ApiError catch (e) {
      // Аккаунт без Telegram: сервер объяснит, почему не вышло.
      if (context.mounted) snack(context, e.message);
    } catch (_) {
      if (context.mounted) snack(context, 'Нет связи с сервером.');
    }
  }

  @override
  Widget build(BuildContext context) => _Page<List<Homework>>(
    load: () async => [for (final h in (await api.get('/homework'))['items'] as List) Homework.fromJson(h)],
    builder: (context, items) {
      final t = now();
      final past = [for (final h in items) if (homeworkPast(h, t)) h];
      final ahead = [for (final h in items) if (!homeworkPast(h, t)) h];
      Widget card(Homework h, {bool past = false}) => Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
        child: Opacity(
          opacity: past ? 0.55 : 1,
          child: _HomeworkCard(h: h, past: past, onSend: () => _send(context, h)),
        ),
      );
      return ListView(
        padding: const EdgeInsets.only(bottom: Space.xxl),
        children: [
          const BackRow(),
          const ScreenTitle(title: 'ДЗ группы'),
          if (items.isEmpty)
            const Notice(
              title: 'Доска ДЗ пока пустая',
              text: 'Староста добавит задания — они появятся тут.',
              pose: CapyPose.joy,
            ),
          for (final h in ahead) card(h),
          if (past.isNotEmpty) ...[
            const Section('Прошло'),
            for (final h in past) card(h, past: true),
          ],
        ],
      );
    },
  );
}

class _HomeworkCard extends StatelessWidget {
  final Homework h;
  final VoidCallback onSend;

  /// Пара уже была — дата без «горящего» цвета.
  final bool past;
  const _HomeworkCard({required this.h, required this.onSend, this.past = false});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    return Tile(
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 3,
              margin: const EdgeInsets.only(right: Space.m),
              decoration: BoxDecoration(color: subjectColor(h.subject), borderRadius: BorderRadius.circular(2)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(h.subject, style: s.body(15, weight: FontWeight.w600)),
                  if (h.content.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(h.content, style: s.body(14, color: p.muted)),
                  ],
                  if (h.lessonDate.isNotEmpty) ...[
                    const SizedBox(height: Space.s),
                    Row(
                      children: [
                        Icon(Icons.event_outlined, size: 14, color: past ? p.muted : p.warn),
                        const SizedBox(width: 4),
                        Text(
                          'к паре · ${shortDay(h.lessonDate)}',
                          style: s.body(12, weight: FontWeight.w600, color: past ? p.muted : p.warn),
                        ),
                      ],
                    ),
                  ],
                  if (h.hasFile) ...[
                    const SizedBox(height: Space.s),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.text,
                        side: BorderSide(color: p.line),
                        shape: const StadiumBorder(),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: onSend,
                      icon: const Icon(Icons.attach_file_rounded, size: 16),
                      label: const Text('Прислать файл'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Note {
  final String subject, text;
  Note.fromJson(Map<String, dynamic> j) : subject = j['subject'] as String? ?? '', text = j['text'] as String? ?? '';
}

/// Заметки к парам: сегодня и завтра — как /note в боте.
class NotesScreen extends StatelessWidget {
  final Api api;
  const NotesScreen({super.key, required this.api});

  Future<List<Note>> _day(DateTime d) async {
    final j = await api.get('/notes?date=${iso(d)}');
    return [for (final n in (j['items'] as List? ?? [])) Note.fromJson(n)];
  }

  @override
  Widget build(BuildContext context) {
    final t = now();
    final today = DateTime(t.year, t.month, t.day);
    final tomorrow = DateTime(t.year, t.month, t.day + 1);
    return _Page<List<List<Note>>>(
      load: () => Future.wait([_day(today), _day(tomorrow)]),
      builder: (context, days) {
        final s = AppStyle.of(context);
        final total = days[0].length + days[1].length;
        return ListView(
          padding: const EdgeInsets.only(bottom: Space.xxl),
          children: [
            const BackRow(),
            const ScreenTitle(title: 'Заметки'),
            if (total == 0)
              const Notice(
                title: 'Заметок нет',
                text: 'Пометку к паре добавляют в боте: /note завтра Матан: контрольная в 401',
                pose: CapyPose.joy,
              ),
            for (final (i, notes) in days.indexed)
              if (notes.isNotEmpty) ...[
                Section(i == 0 ? 'Сегодня · ${shortDay(iso(today))}' : 'Завтра · ${shortDay(iso(tomorrow))}'),
                for (final n in notes)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                    child: Tile(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.push_pin_outlined, size: 18, color: s.p.accent),
                          const SizedBox(width: Space.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (n.subject.isNotEmpty) Text(n.subject, style: s.body(15, weight: FontWeight.w600)),
                                Text(n.text, style: s.body(15)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            if (total > 0)
              Padding(
                padding: const EdgeInsets.fromLTRB(Space.xl, Space.l, Space.xl, 0),
                child: Text('Добавить — в боте: /note завтра Предмет: текст', style: s.body(13, color: s.p.muted)),
              ),
          ],
        );
      },
    );
  }
}
