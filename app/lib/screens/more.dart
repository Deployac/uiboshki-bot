// «Ещё» — кто я и из какой группы, уведомления, безопасность, предметы по
// выбору, календарь в телефоне, шрифт, тема, выход.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../api/links.dart';
import 'notify.dart';
import 'security.dart';

class MoreScreen extends StatelessWidget {
  final Api api;
  final ValueChanged<FontChoice> onFont;
  final VoidCallback onLogout;
  final VoidCallback? onUnauthorized;

  /// «Группа» → выбрать другую (оболочка перестроит экраны).
  final VoidCallback? onGroup;
  const MoreScreen({
    super.key,
    required this.api,
    required this.onFont,
    required this.onLogout,
    this.onUnauthorized,
    this.onGroup,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    return Loader<Map<String, dynamic>>(
      load: () async => Map<String, dynamic>.from(await api.get('/me')),
      onUnauthorized: onUnauthorized,
      builder: (context, me, _) => ListView(
        padding: const EdgeInsets.only(bottom: 120),
        children: [
          ScreenTitle(eyebrow: 'профиль и настройки', title: me['first_name'] ?? 'Ещё'),
          const Section('Моя группа'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: Tile(
              onTap: onGroup,
              child: Row(
                children: [
                  Icon(Icons.groups_outlined, color: p.accent),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(me['group']?['name'] ?? 'не выбрана', style: s.body(16, weight: FontWeight.w600)),
                        Text('расписание и сроки — этой группы', style: s.body(13, color: p.muted)),
                      ],
                    ),
                  ),
                  Text(
                    'Сменить',
                    style: s.body(14, weight: FontWeight.w600, color: p.accent),
                  ),
                ],
              ),
            ),
          ),
          if (me['group'] != null && me['group']['own'] != true)
            Padding(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
              child: _AdminRequest(api: api),
            ),
          const Section('Шрифт'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: Row(
              children: [
                for (final f in FontChoice.values) ...[
                  if (f != FontChoice.values.first) const SizedBox(width: Space.s),
                  Expanded(
                    child: _FontCard(choice: f, selected: s.font == f, onTap: () => onFont(f)),
                  ),
                ],
              ],
            ),
          ),
          const Section('Тема'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: Tile(
              child: Row(
                children: [
                  Icon(p.dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined, color: p.accent),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Text(
                      p.dark ? '«Глубина» — тёмная, как в телефоне' : '«Тетрадь» — светлая, как в телефоне',
                      style: s.body(15),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _Optional(api: api),
          const Section('Настройки'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: Tile(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _MenuRow(
                    icon: Icons.notifications_none_rounded,
                    title: 'Уведомления',
                    sub: 'утро, пары, дедлайны — что и в какие дни',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => NotifyScreen(api: api, onUnauthorized: onUnauthorized),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: p.line),
                  _MenuRow(
                    icon: Icons.shield_outlined,
                    title: 'Безопасность',
                    sub: 'устройства, вход без Telegram',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => SecurityScreen(api: api, onLogout: onLogout, onUnauthorized: onUnauthorized),
                      ),
                    ),
                  ),
                  Divider(height: 1, color: p.line),
                  _MenuRow(
                    icon: Icons.event_available_outlined,
                    title: 'Календарь в телефоне',
                    sub: 'пары и дедлайны — подпиской',
                    onTap: () => _copyCalendar(context),
                  ),
                  Divider(height: 1, color: p.line),
                  _MenuRow(
                    icon: Icons.group_add_outlined,
                    title: 'Позвать',
                    sub: 'ссылка на бота — для одногруппников',
                    onTap: () => _invite(context),
                  ),
                  _LinkRows(api: api),
                ],
              ),
            ),
          ),
          const Section('Аккаунт'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.l),
            child: Tile(
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Выйти?'),
                    content: const Text('На этом устройстве. Войти снова — через бота.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Остаться')),
                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти')),
                    ],
                  ),
                );
                if (ok == true) onLogout();
              },
              child: Row(
                children: [
                  Icon(Icons.logout_rounded, color: p.danger),
                  const SizedBox(width: Space.m),
                  Text(
                    'Выйти',
                    style: s.body(15, weight: FontWeight.w600, color: p.danger),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Адрес сервера для ссылок наружу (на стенде base пустой — тот же сайт).
  static String get _origin => Api.base.isEmpty ? Uri.base.origin : Api.base;

  void _snack(BuildContext context, String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  // Подписка на расписание и дедлайны в календаре телефона (как /calendar в боте)
  Future<void> _copyCalendar(BuildContext context) async {
    try {
      final r = await api.get('/calendar/link');
      await Clipboard.setData(ClipboardData(text: '$_origin${r['ics_path']}'));
      if (context.mounted) _snack(context, 'Ссылка скопирована — Календарь → Добавить подписку');
    } catch (e) {
      if (context.mounted) _snack(context, 'Не вышло: $e');
    }
  }

  // «Позвать»: ссылка на сайт бота (/about — живое демо и поиск расписания)
  Future<void> _invite(BuildContext context) async {
    await Clipboard.setData(
      ClipboardData(text: 'Бот нашей группы: расписание, дедлайны и баллы СДО, лекции и ИИ по ним — $_origin/about'),
    );
    if (context.mounted) _snack(context, 'Ссылка скопирована — отправь одногруппникам');
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String title, sub;
  final VoidCallback onTap;
  const _MenuRow({required this.icon, required this.title, required this.sub, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    return InkWell(
      onTap: () {
        tick();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
        child: Row(
          children: [
            Icon(icon, color: s.p.accent),
            const SizedBox(width: Space.m),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: s.body(16, weight: FontWeight.w600)),
                  Text(sub, style: s.body(13, color: s.p.muted)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: s.p.muted),
          ],
        ),
      ),
    );
  }
}

/// Предметы по выбору (военная кафедра): «хожу» — пары в расписании, «не хожу» —
/// скрыты (optional_subjects.py). Нет таких в расписании группы — блока нет.
class _Optional extends StatefulWidget {
  final Api api;
  const _Optional({required this.api});

  @override
  State<_Optional> createState() => _OptionalState();
}

class _OptionalState extends State<_Optional> {
  List<String> _pending = [];
  Map<String, bool> _answers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.api.get('/optional');
      if (!mounted) return;
      setState(() {
        _pending = [for (final x in (r['pending'] as List? ?? const [])) x as String];
        _answers = {for (final e in ((r['answers'] as Map?) ?? const {}).entries) e.key as String: e.value == true};
      });
    } catch (_) {}
  }

  Future<void> _answer(String subject, bool attend) async {
    tick();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.api.post('/optional', {'subject': subject, 'attend': attend});
    } on ApiError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Не сохранилось: ${e.message}')));
      return;
    }
    if (!mounted) return;
    setState(() {
      _pending.remove(subject);
      _answers[subject] = attend;
    });
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(attend ? 'Пары «$subject» будут в расписании' : 'Убрал «$subject» из расписания')),
      );
  }

  @override
  Widget build(BuildContext context) {
    final subjects = [..._pending, ..._answers.keys.where((k) => !_pending.contains(k))];
    if (subjects.isEmpty) return const SizedBox.shrink();
    final s = AppStyle.of(context);
    final p = s.p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Section('Предметы по выбору'),
        for (final subj in subjects)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
            child: Tile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.military_tech_outlined, color: p.accent),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: Text(subj, style: s.body(16, weight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _pending.contains(subj)
                        ? 'Ходишь? Если нет — уберу эти пары из твоего расписания.'
                        : (_answers[subj]! ? 'Хожу — пары в расписании' : 'Не хожу — пары скрыты'),
                    style: s.body(13, color: p.muted),
                  ),
                  const SizedBox(height: Space.m),
                  Row(
                    children: [
                      for (final attend in [true, false]) ...[
                        if (!attend) const SizedBox(width: Space.s),
                        Expanded(
                          child: _Choice(
                            text: attend ? 'Хожу' : 'Не хожу',
                            on: _answers[subj] == attend,
                            onTap: () => _answer(subj, attend),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Choice extends StatelessWidget {
  final String text;
  final bool on;
  final VoidCallback onTap;
  const _Choice({required this.text, required this.on, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final r = BorderRadius.circular(Radii.chip);
    return Material(
      color: on ? p.accent : p.line,
      borderRadius: r,
      child: InkWell(
        borderRadius: r,
        onTap: on ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.m),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: s.body(15, weight: FontWeight.w600, color: on ? p.onAccent : p.text),
          ),
        ),
      ),
    );
  }
}

class _FontCard extends StatelessWidget {
  final FontChoice choice;
  final bool selected;
  final VoidCallback onTap;
  const _FontCard({required this.choice, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final book = choice == FontChoice.book;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.tile),
        border: Border.all(color: selected ? p.accent : Colors.transparent, width: 2),
      ),
      child: Tile(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Аа 73',
              style: TextStyle(
                fontFamily: book ? 'SourceSerif' : 'Onest',
                fontSize: 30,
                fontWeight: book ? FontWeight.w500 : FontWeight.w800,
                color: p.text,
              ),
            ),
            const SizedBox(height: 4),
            Text(book ? 'Книжный' : 'Строгий', style: s.body(14, weight: FontWeight.w600)),
            Text(book ? 'с засечками' : 'ровный, Onest', style: s.body(12, color: p.muted)),
          ],
        ),
      ),
    );
  }
}

/// «Я староста этой группы» — запрос владельцу бота (одобрит — можно вести
/// общие сроки, ДЗ и заметки группы).
class _AdminRequest extends StatefulWidget {
  final Api api;
  const _AdminRequest({required this.api});

  @override
  State<_AdminRequest> createState() => _AdminRequestState();
}

class _AdminRequestState extends State<_AdminRequest> {
  String? _note;

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    return Tile(
      onTap: _note != null
          ? null
          : () async {
              try {
                await widget.api.post('/me/group/admin');
                setState(() => _note = 'Запрос отправлен — ответ придёт в бота.');
              } on ApiError catch (e) {
                setState(() => _note = e.message);
              }
            },
      padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.m),
      child: Row(
        children: [
          Icon(Icons.verified_user_outlined, color: s.p.muted, size: 20),
          const SizedBox(width: Space.m),
          Expanded(child: Text(_note ?? 'Я староста этой группы', style: s.body(15))),
        ],
      ),
    );
  }
}

/// «Канал бота» и «Написать нам» — если сервер их знает (/api/meta → links).
class _LinkRows extends StatelessWidget {
  final Api api;
  const _LinkRows({required this.api});

  @override
  Widget build(BuildContext context) {
    final p = AppStyle.of(context).p;
    return FutureBuilder<Map<String, String>>(
      future: appLinks(api),
      builder: (context, snap) {
        final l = snap.data ?? const {};
        final rows = [
          if ((l['channel'] ?? '').isNotEmpty)
            (Icons.campaign_outlined, 'Канал бота', 'новости и как всё устроено', _url(l['channel']!)),
          if ((l['contact'] ?? '').isNotEmpty)
            (Icons.chat_bubble_outline_rounded, 'Написать нам', 'идея, ошибка, вопрос', _url(l['contact']!)),
        ];
        return Column(
          children: [
            for (final (icon, title, sub, url) in rows) ...[
              Divider(height: 1, color: p.line),
              _MenuRow(
                icon: icon,
                title: title,
                sub: sub,
                onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
              ),
            ],
          ],
        );
      },
    );
  }

  /// «@имя» → https://t.me/имя
  static String _url(String v) => v.startsWith('@') ? 'https://t.me/${v.substring(1)}' : v;
}
