// «Сдать» — сроки: самый горящий крупно с обратным отсчётом, дальше
// «Сегодня и завтра», «На неделе», «Позже», «Сдано». Свайп вправо — «сдал»,
// нажатие — действия (изменить, напомнить, убрать…), «+» — свой срок.
// Сверху — входы в «ДЗ группы» и «Заметки».
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/capy.dart';
import '../widgets/common.dart';
import 'deadline_edit.dart';
import 'homework.dart';
import 'submit.dart';

typedef _Items = ({List<Deadline> list, Map<int, DlExtra> extra});

class DeadlinesScreen extends StatefulWidget {
  final Api api;
  final VoidCallback? onUnauthorized;
  const DeadlinesScreen({super.key, required this.api, this.onUnauthorized});

  @override
  State<DeadlinesScreen> createState() => _DeadlinesScreenState();
}

class _DeadlinesScreenState extends State<DeadlinesScreen> {
  Future<_Items> _load() async {
    final j = await widget.api.get('/deadlines?include_done=true');
    final raw = [for (final x in j['items'] as List) Map<String, dynamic>.from(x)];
    return (
      list: [for (final x in raw) Deadline.fromJson(x)],
      extra: {for (final x in raw) x['id'] as int: DlExtra.fromJson(x)},
    );
  }

  /// Запрос с ошибкой внизу экрана; true — прошёл.
  Future<bool> _run(Future<void> Function() call) async {
    try {
      await call();
      return true;
    } on ApiError catch (e) {
      if (mounted) snack(context, e.message);
    } catch (_) {
      if (mounted) snack(context, 'Нет связи с сервером.');
    }
    return false;
  }

  Future<void> _toggle(Deadline d, bool done) async {
    await _run(() => widget.api.post('/deadlines/${d.id}/toggle', {'done': done}));
  }

  Future<void> _submit(Deadline d, Future<void> Function() reload) async {
    final ok = await showSubmitSheet(context, widget.api, title: d.subject, deadlineId: d.id);
    if (ok == true) await reload();
  }

  Future<void> _actions(Deadline d, DlExtra x, Future<void> Function() reload) async {
    final api = widget.api;
    final due = _dueLabel(d);
    final a = await showDeadlineActions(context, d, x, due: due);
    if (a == null || !mounted) return;
    switch (a) {
      case DlAction.submit:
        await _submit(d, reload);
      case DlAction.task:
        await launchUrl(Uri.parse(x.description), mode: LaunchMode.externalApplication);
      case DlAction.remind:
        await showRemindSheet(context, api, d, x, due: due);
        await reload();
      case DlAction.done || DlAction.undone:
        await _toggle(d, a == DlAction.done);
        await reload();
      case DlAction.edit:
        final saved = await showDeadlineEdit(context, api, d: d, x: x);
        if (saved == true) {
          if (mounted) snack(context, x.editScope == 'me' && !x.personal ? 'Сохранено у тебя' : 'Сохранено');
          await reload();
        }
      case DlAction.delete:
        if (!await confirmDelete(context, x)) return;
        if (await _run(() => api.delete('/deadlines/${d.id}'))) await reload();
      case DlAction.resetMine:
        if (await _run(() => api.delete('/deadlines/${d.id}/mine'))) {
          if (mounted) snack(context, 'Снова как у всей группы');
          await reload();
        }
    }
  }

  Future<void> _add(Future<void> Function() reload) async {
    tick();
    final saved = await showDeadlineEdit(context, widget.api);
    if (saved == true) {
      if (mounted) snack(context, 'Срок добавлен — видишь только ты');
      await reload();
    }
  }

  @override
  Widget build(BuildContext context) => Loader<_Items>(
    load: _load,
    onUnauthorized: widget.onUnauthorized,
    builder: (context, items, reload) => _DeadlinesView(
      items: items.list,
      extra: items.extra,
      api: widget.api,
      onAdd: () => _add(reload),
      onOpen: (d) => _actions(d, items.extra[d.id] ?? DlExtra.fromJson(const {}), reload),
      onSubmit: (d) => _submit(d, reload),
      onToggle: (d, done) async {
        await _toggle(d, done);
        await reload();
      },
    ),
  );
}

class _DeadlinesView extends StatelessWidget {
  final List<Deadline> items;
  final Map<int, DlExtra> extra;
  final Api api;
  final Future<void> Function(Deadline, bool) onToggle;
  final ValueChanged<Deadline> onSubmit, onOpen;
  final VoidCallback onAdd;
  const _DeadlinesView({
    required this.items,
    required this.extra,
    required this.api,
    required this.onToggle,
    required this.onSubmit,
    required this.onOpen,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final p = AppStyle.of(context).p;
    final t = now();
    final open = items.where((d) => !d.done && d.due.isAfter(t)).toList()..sort((a, b) => a.due.compareTo(b.due));
    final late = items.where((d) => !d.done && !d.due.isAfter(t)).toList();
    final done = items.where((d) => d.done).toList();
    final hot = open.firstOrNull;
    // самый горящий — крупно сверху, в списках его не повторяем
    final soon = open.where((d) => d.due.difference(t).inHours < 48).toList();
    final week = open.where((d) => d != hot && !soon.contains(d) && d.due.difference(t).inDays < 7).toList();
    final later = open.where((d) => d != hot && !soon.contains(d) && !week.contains(d)).toList();
    final dayEnd = DateTime(t.year, t.month, t.day + 1);
    final burning = open.where((d) => d.due.isBefore(dayEnd)).length;

    Widget row(Deadline d) => Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
      child: _Row(d: d, x: extra[d.id], at: t, onToggle: onToggle, onOpen: onOpen),
    );

    void push(Widget screen) => Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        ScreenTitle(
          eyebrow: [
            if (burning > 0) '$burning ${plural(burning, 'горит', 'горят', 'горят')}',
            '${open.length} впереди',
            '${done.length} сдано',
          ].join(' · '),
          title: 'Сдать',
          trailing: IconButton.filled(
            tooltip: 'Свой срок',
            style: IconButton.styleFrom(backgroundColor: p.accent, foregroundColor: p.onAccent),
            onPressed: onAdd,
            icon: const Icon(Icons.add_rounded),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
          child: Row(
            children: [
              Expanded(
                child: _Entry(
                  icon: Icons.assignment_outlined,
                  text: 'ДЗ группы',
                  onTap: () => push(HomeworkScreen(api: api)),
                ),
              ),
              const SizedBox(width: Space.s),
              Expanded(
                child: _Entry(
                  icon: Icons.push_pin_outlined,
                  text: 'Заметки',
                  onTap: () => push(NotesScreen(api: api)),
                ),
              ),
            ],
          ),
        ),
        if (hot != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: _Hot(
              d: hot,
              x: extra[hot.id],
              at: t,
              onDone: () => onToggle(hot, true),
              onSubmit: () => onSubmit(hot),
              onOpen: () => onOpen(hot),
            ),
          ),
        if (open.isEmpty)
          const Notice(
            title: 'Всё сдано',
            text: 'Новые задания из СДО появятся здесь сами. Свой срок — кнопкой +.',
            pose: CapyPose.joy,
          ),
        if (soon.length > 1) ...[const Section('Сегодня и завтра'), for (final d in soon.skip(1)) row(d)],
        if (week.isNotEmpty) ...[const Section('На неделе'), for (final d in week) row(d)],
        if (later.isNotEmpty) ...[const Section('Позже'), for (final d in later) row(d)],
        if (late.isNotEmpty) ...[const Section('Срок прошёл'), for (final d in late) row(d)],
        if (done.isNotEmpty) ...[const Section('Сдано'), for (final d in done) row(d)],
      ],
    );
  }
}

/// Плитка-вход: «ДЗ группы», «Заметки».
class _Entry extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  const _Entry({required this.icon, required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    return Tile(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.m),
      child: Row(
        children: [
          Icon(icon, size: 20, color: s.p.accent),
          const SizedBox(width: Space.s),
          Expanded(
            child: Text(text, style: s.body(15, weight: FontWeight.w600)),
          ),
          Icon(Icons.chevron_right_rounded, size: 20, color: s.p.muted),
        ],
      ),
    );
  }
}

/// Пометки на карточке — только если есть что показать.
bool _hasChips(DlExtra? x) => x != null && (x.personal || x.mineChanged || x.reminders.isNotEmpty);

String _dueLabel(Deadline d) {
  final due = d.due;
  return '${weekdaysShort[due.weekday - 1].toLowerCase()}, ${due.day} ${monthsGen[due.month - 1]} · ${d.dueTime.isEmpty ? '23:59' : d.dueTime}';
}

class _Hot extends StatelessWidget {
  final Deadline d;
  final DlExtra? x;
  final DateTime at;
  final VoidCallback onDone, onSubmit, onOpen;
  const _Hot({
    required this.d,
    required this.x,
    required this.at,
    required this.onDone,
    required this.onSubmit,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final left = d.due.difference(at);
    final c = left.inHours < 24 ? p.danger : p.warn;
    final h = left.inHours, m = left.inMinutes % 60;
    return Tile(
      onTap: onOpen,
      radius: Radii.card,
      gradient: LinearGradient(
        begin: Alignment.topRight,
        end: Alignment.bottomLeft,
        colors: [
          c.withValues(alpha: p.dark ? 0.38 : 0.22),
          p.cardSolid.withValues(alpha: p.dark ? 0.6 : 1),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text('до ${_dueLabel(d)}', style: s.eyebrow(color: c)),
              ),
            ],
          ),
          const SizedBox(height: Space.s),
          Text(d.subject, style: s.title(21)),
          if (_hasChips(x)) ...[const SizedBox(height: Space.s), DlChips(x: x!)],
          const SizedBox(height: Space.m),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (h >= 48) ...[
                  Text('${left.inDays}', style: s.number(56, color: c)),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(plural(left.inDays, 'день', 'дня', 'дней'), style: s.body(14, color: p.muted)),
                  ),
                ] else ...[
                  Text('$h', style: s.number(56, color: c)),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 3, right: 10),
                    child: Text('ч', style: s.body(14, color: p.muted)),
                  ),
                  Text(m.toString().padLeft(2, '0'), style: s.number(56, color: c)),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 3),
                    child: Text('мин', style: s.body(14, color: p.muted)),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: Space.l),
          Wrap(
            spacing: Space.s,
            runSpacing: Space.s,
            children: [
              if (d.canSubmit)
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: c,
                    foregroundColor: Colors.white,
                    shape: const StadiumBorder(),
                  ),
                  onPressed: () {
                    tick();
                    onSubmit();
                  },
                  icon: const Icon(Icons.upload_rounded, size: 18),
                  label: const Text('Сдать файлом'),
                ),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.text,
                  side: BorderSide(color: p.line),
                  shape: const StadiumBorder(),
                ),
                onPressed: () {
                  tick();
                  onDone();
                },
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text('Уже сдал'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final Deadline d;
  final DlExtra? x;
  final DateTime at;
  final Future<void> Function(Deadline, bool) onToggle;
  final ValueChanged<Deadline> onOpen;
  const _Row({required this.d, required this.x, required this.at, required this.onToggle, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final color = subjectColor(d.subject.contains(' · ') ? d.subject.split(' · ').last : d.subject);
    final tile = Tile(
      onTap: () => onOpen(d),
      padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
      child: Opacity(
        opacity: d.done ? 0.5 : 1,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                margin: const EdgeInsets.only(right: Space.m),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.subject,
                      style: s
                          .body(15, weight: FontWeight.w600)
                          .copyWith(decoration: d.done ? TextDecoration.lineThrough : null),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      d.done ? 'сдано' : '${_dueLabel(d)} · ${leftText(d.due.difference(at))}',
                      style: s.body(13, color: p.muted),
                    ),
                    if (_hasChips(x)) ...[const SizedBox(height: 6), DlChips(x: x!)],
                  ],
                ),
              ),
              if (d.done) Icon(Icons.check_rounded, color: p.ok, size: 20),
            ],
          ),
        ),
      ),
    );
    return Dismissible(
      key: ValueKey('dl-${d.id}-${d.done}'),
      direction: DismissDirection.startToEnd,
      confirmDismiss: (_) async {
        tick();
        await onToggle(d, !d.done);
        return false;
      },
      background: Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: Space.xl),
        decoration: BoxDecoration(color: d.done ? p.muted : p.ok, borderRadius: BorderRadius.circular(Radii.tile)),
        child: Text(
          d.done ? 'Вернуть' : 'Сдано',
          style: s.body(15, weight: FontWeight.w700, color: Colors.white),
        ),
      ),
      child: tile,
    );
  }
}
