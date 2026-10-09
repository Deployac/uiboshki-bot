// «Уведомления» — что бот присылает и в какие дни (/api/notify, notify_prefs.py).
// Как лист в WebApp: сохраняется сразу при каждом нажатии, без «Сохранить».
import 'package:flutter/material.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'files.dart' show BackRow;

class NotifyScreen extends StatelessWidget {
  final Api api;
  final VoidCallback? onUnauthorized;
  const NotifyScreen({super.key, required this.api, this.onUnauthorized});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Backdrop(
      child: SafeArea(
        child: Loader<Map<String, dynamic>>(
          load: () async => Map<String, dynamic>.from(await api.get('/notify')),
          onUnauthorized: onUnauthorized,
          builder: (context, data, _) => _NotifyBody(api: api, initial: data),
        ),
      ),
    ),
  );
}

class _NotifyBody extends StatefulWidget {
  final Api api;
  final Map<String, dynamic> initial;
  const _NotifyBody({required this.api, required this.initial});

  @override
  State<_NotifyBody> createState() => _NotifyBodyState();
}

class _NotifyBodyState extends State<_NotifyBody> {
  late Map<String, dynamic> _s = widget.initial;

  // Быстрые нажатия (Пн, Вт, Ср подряд) не теряются: у себя меняем сразу,
  // запросы уходят по очереди, ответ сервера берём от последнего.
  Future<void> _queue = Future.value();
  int _pending = 0;

  @override
  void didUpdateWidget(_NotifyBody old) {
    super.didUpdateWidget(old);
    if (old.initial != widget.initial && _pending == 0) _s = widget.initial; // потянули — свежие с сервера
  }

  Map<String, dynamic> get _prefs => _s['prefs'] as Map<String, dynamic>;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _save(Map<String, dynamic> body) {
    tick();
    setState(() {
      if (body.containsKey('subscribed')) _s['subscribed'] = body['subscribed'];
      if (body['prefs'] is Map) _prefs.addAll(Map<String, dynamic>.from(body['prefs'] as Map));
    });
    _pending++;
    return _queue = _queue.then((_) async {
      Object? fresh;
      try {
        fresh = await widget.api.post('/notify', body);
      } catch (e) {
        _snack('Не сохранилось: $e');
        try {
          fresh = await widget.api.get('/notify'); // что на самом деле сохранено
        } catch (_) {}
      }
      if (--_pending == 0 && fresh is Map && fresh['prefs'] is Map && mounted) {
        setState(() => _s = Map<String, dynamic>.from(fresh as Map));
      }
    });
  }

  void _toggle(String key) => _save({
    'prefs': {key: !(_prefs[key] == true)},
  });

  void _toggleDay(String key, int day) {
    final days = List<int>.from(_prefs[key] as List);
    days.contains(day) ? days.remove(day) : days.add(day);
    days.sort();
    _save({
      'prefs': {key: days},
    });
  }

  Future<void> _customRemind(Map r) async {
    final key = r['key'] as String;
    final max = r['max'] as int;
    final v = _prefs[key] as int? ?? 0;
    final ctrl = TextEditingController(text: v > 0 && !(r['presets'] as List).contains(v) ? '$v' : '');
    final n = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(r['title'] as String),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: 'минут до пары, до $max'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Отмена')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, int.tryParse(ctrl.text.trim()) ?? -1),
            child: const Text('OK'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (n == null) return;
    if (n < 1 || n > max) {
      _snack('Число минут от 1 до $max');
      return;
    }
    _save({
      'prefs': {key: n},
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final on = _s['subscribed'] == true;
    final campus = _s['home_campus'] as String?;
    return ListView(
      padding: const EdgeInsets.only(bottom: Space.xxl),
      children: [
        const BackRow(),
        const ScreenTitle(eyebrow: 'что бот присылает и когда', title: 'Уведомления'),
        Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.m),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 18, color: p.muted),
              const SizedBox(width: Space.s),
              Expanded(
                child: Text(
                  'Уведомления в Telegram и пушами PWA; пуши приложения — скоро.',
                  style: s.body(13, color: p.muted),
                ),
              ),
            ],
          ),
        ),
        _Card(
          title: 'Присылать уведомления',
          sub: on ? 'Включены — ниже, что именно' : 'Выключены — бот ничего не пришлёт сам',
          switchKey: 'subscribed',
          on: on,
          onChanged: () => _save({'subscribed': !on}),
        ),
        if (on) ...[
          _Card(
            icon: Icons.wb_sunny_outlined,
            title: 'Утреннее расписание',
            sub: 'в ${_s['morning_time'] ?? '8:00'} — пары на сегодня',
            switchKey: 'morning',
            on: _prefs['morning'] == true,
            onChanged: () => _toggle('morning'),
            children: [
              _Days(days: _prefs['morning_days'] as List, daysKey: 'morning_days', onTap: _toggleDay),
              _Row(title: 'Погода', sub: 'строчка с погодой в начале', k: 'weather', prefs: _prefs, onTap: _toggle),
              _Row(
                title: 'Другой корпус',
                sub: campus != null ? 'если пары не на $campus — напишу, где' : 'если пары в другом корпусе — напишу',
                k: 'campus',
                prefs: _prefs,
                onTap: _toggle,
              ),
              _Row(
                title: 'Только если есть пары',
                sub: 'в свободный день — тишина',
                k: 'skip_empty',
                prefs: _prefs,
                onTap: _toggle,
              ),
            ],
          ),
          _Card(
            icon: Icons.alarm_outlined,
            title: 'Перед парой',
            sub: 'своё время для первой пары и после перемены',
            switchKey: 'lessons',
            on: _prefs['lessons'] == true,
            onChanged: () => _toggle('lessons'),
            children: [
              _Days(days: _prefs['lesson_days'] as List, daysKey: 'lesson_days', onTap: _toggleDay),
              for (final r in (_s['remind'] as List? ?? const []))
                _Remind(
                  r: r as Map,
                  value: _prefs[r['key']] as int? ?? 0,
                  onPick: (v) => _save({
                    'prefs': {r['key'] as String: v},
                  }),
                  onCustom: () => _customRemind(r),
                ),
            ],
          ),
          _Card(
            icon: Icons.flag_outlined,
            title: 'Дедлайны',
            sub: 'в ${_s['deadline_time'] ?? '19:00'} — что сдать в ближайшие 3 дня',
            switchKey: 'deadlines',
            on: _prefs['deadlines'] == true,
            onChanged: () => _toggle('deadlines'),
            children: [_Days(days: _prefs['deadline_days'] as List, daysKey: 'deadline_days', onTap: _toggleDay)],
          ),
          _Card(
            icon: Icons.view_week_outlined,
            title: 'Обзор недели',
            sub: 'в воскресенье в 19:00 — пары по дням и что сдать',
            switchKey: 'weekly',
            on: _prefs['weekly'] == true,
            onChanged: () => _toggle('weekly'),
          ),
          _Card(
            icon: Icons.military_tech_outlined,
            title: 'Новые баллы',
            sub: 'когда в СДО изменятся баллы (если подключён вход)',
            switchKey: 'grades',
            on: _prefs['grades'] == true,
            onChanged: () => _toggle('grades'),
          ),
          _Card(
            icon: Icons.assignment_outlined,
            title: 'Новые задания',
            sub: 'когда в СДО появится задание или перенесут срок',
            switchKey: 'new_tasks',
            on: _prefs['new_tasks'] == true,
            onChanged: () => _toggle('new_tasks'),
          ),
        ],
      ],
    );
  }
}

/// Переключатель в цветах темы; ключ — для тестов («notify:weather»).
class AppSwitch extends StatelessWidget {
  final bool value;
  final VoidCallback onChanged;
  const AppSwitch({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = AppStyle.of(context).p;
    return Switch(
      value: value,
      onChanged: (_) => onChanged(),
      activeTrackColor: p.accent,
      activeThumbColor: p.onAccent,
      inactiveTrackColor: p.line,
      inactiveThumbColor: p.muted,
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    );
  }
}

/// Карточка вида уведомлений: значок, что и когда, выключатель; включена — настройки ниже.
class _Card extends StatelessWidget {
  final IconData? icon;
  final String title, sub, switchKey;
  final bool on;
  final VoidCallback onChanged;
  final List<Widget> children;
  const _Card({
    this.icon,
    required this.title,
    required this.sub,
    required this.switchKey,
    required this.on,
    required this.onChanged,
    this.children = const [],
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
      child: Tile(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: on ? 0.16 : 0.06),
                      borderRadius: BorderRadius.circular(Radii.chip),
                    ),
                    child: Icon(icon, size: 20, color: on ? p.accent : p.muted),
                  ),
                  const SizedBox(width: Space.m),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: s.body(16, weight: FontWeight.w600, color: on ? p.text : p.muted),
                      ),
                      Text(sub, style: s.body(13, color: p.muted)),
                    ],
                  ),
                ),
                AppSwitch(key: Key('notify:$switchKey'), value: on, onChanged: onChanged),
              ],
            ),
            if (on && children.isNotEmpty) ...[const SizedBox(height: Space.m), ...children],
          ],
        ),
      ),
    );
  }
}

/// Строка-выключатель внутри карточки: погода, корпус, «только если есть пары».
class _Row extends StatelessWidget {
  final String title, sub, k;
  final Map<String, dynamic> prefs;
  final ValueChanged<String> onTap;
  const _Row({required this.title, required this.sub, required this.k, required this.prefs, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Space.s),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: s.body(15, weight: FontWeight.w500)),
                Text(sub, style: s.body(12, color: s.p.muted)),
              ],
            ),
          ),
          AppSwitch(key: Key('notify:$k'), value: prefs[k] == true, onChanged: () => onTap(k)),
        ],
      ),
    );
  }
}

/// Дни недели: Пн…Вс, выходные — приглушённее.
class _Days extends StatelessWidget {
  final List days;
  final String daysKey;
  final void Function(String key, int day) onTap;
  const _Days({required this.days, required this.daysKey, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    return Row(
      children: [
        for (var i = 0; i < 7; i++) ...[
          if (i > 0) const SizedBox(width: Space.xs),
          Expanded(
            child: _Pill(
              key: Key('days:$daysKey:$i'),
              text: weekdaysShort[i],
              on: days.contains(i),
              dim: i >= 5,
              onTap: () => onTap(daysKey, i),
              color: p.accent,
            ),
          ),
        ],
      ],
    );
  }
}

/// Напоминание по сценарию: «выкл», пресеты и «своё».
class _Remind extends StatelessWidget {
  final Map r;
  final int value;
  final ValueChanged<int> onPick;
  final VoidCallback onCustom;
  const _Remind({required this.r, required this.value, required this.onPick, required this.onCustom});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final presets = [for (final m in r['presets'] as List) m as int];
    final own = value > 0 && !presets.contains(value);
    Widget chip(String text, bool on, VoidCallback tap) =>
        _Pill(key: Key('remind:${r['key']}:$text'), text: text, on: on, onTap: tap, color: s.p.accent, wide: true);
    return Padding(
      padding: const EdgeInsets.only(top: Space.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            r['title'] as String,
            style: s.body(13, weight: FontWeight.w600, color: s.p.muted),
          ),
          const SizedBox(height: Space.xs),
          Wrap(
            spacing: Space.xs,
            runSpacing: Space.xs,
            children: [
              chip('выкл', value == 0, () => onPick(0)),
              for (final m in presets) chip(minText(m), value == m, () => onPick(m)),
              chip(own ? minText(value) : 'своё', own, onCustom),
            ],
          ),
        ],
      ),
    );
  }
}

/// «1 ч 30 мин», «5 мин».
String minText(int m) => [if (m ~/ 60 > 0) '${m ~/ 60} ч', if (m % 60 > 0) '${m % 60} мин'].join(' ');

class _Pill extends StatelessWidget {
  final String text;
  final bool on, dim, wide;
  final VoidCallback onTap;
  final Color color;
  const _Pill({
    super.key,
    required this.text,
    required this.on,
    required this.onTap,
    required this.color,
    this.dim = false,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    return Material(
      // line в тёмной теме полупрозрачная: альфу только уменьшаем (было alpha: 1 —
      // невыбранные плашки становились белыми с белым текстом)
      color: on ? color : p.line.withValues(alpha: p.line.a * (dim ? 0.5 : 1)),
      borderRadius: BorderRadius.circular(Radii.chip),
      child: InkWell(
        borderRadius: BorderRadius.circular(Radii.chip),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: wide ? Space.m : 0, vertical: Space.s),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: s.body(13, weight: FontWeight.w600, color: on ? p.onAccent : (dim ? p.muted : p.text)),
          ),
        ),
      ),
    );
  }
}
