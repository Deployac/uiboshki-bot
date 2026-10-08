// «Безопасность» — устройства со входом, вход без Telegram (VK, Яндекс) и
// коротко, как защищены данные (/api/security, как openSecurity в WebApp).
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'files.dart' show BackRow;

typedef _Data = ({List sessions, Map? identities, Map security});

class SecurityScreen extends StatefulWidget {
  final Api api;

  /// Вышли на этом устройстве — оболочка покажет экран входа.
  final VoidCallback onLogout;
  final VoidCallback? onUnauthorized;

  /// Открыть ссылку привязки в браузере (в тестах — подмена).
  final Future<void> Function(Uri url)? open;
  const SecurityScreen({super.key, required this.api, required this.onLogout, this.onUnauthorized, this.open});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  // Вернулись из браузера после «Да, привязать» — список входов обновится сам.
  late final AppLifecycleListener _life;
  int _epoch = 0;

  Api get api => widget.api;

  @override
  void initState() {
    super.initState();
    _life = AppLifecycleListener(onResume: () => setState(() => _epoch++));
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  Future<_Data> _load() async {
    final r = await Future.wait([
      api.get('/auth/sessions'),
      api.get('/auth/identities').then<Object?>((v) => v, onError: (_) => null),
      api.get('/security').then<Object?>((v) => v, onError: (_) => const {}),
    ]);
    return (
      sessions: (r[0] as Map?)?['items'] as List? ?? const [],
      identities: r[1] is Map ? r[1] as Map : null,
      security: r[2] is Map ? r[2] as Map : const {},
    );
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// Вышли на этом телефоне — закрыть экран и уйти ко входу.
  void _leave() {
    Navigator.of(context).popUntil((r) => r.isFirst);
    widget.onLogout();
  }

  Future<void> _revoke(Map d) async {
    tick();
    try {
      await api.delete('/auth/sessions/${d['id']}');
    } on ApiError catch (e) {
      _snack(e.message);
      return;
    }
    if (d['current'] == true) return _leave();
    setState(() => _epoch++);
  }

  Future<void> _everywhere() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Выйти везде?'),
        content: const Text('На всех устройствах, и на этом тоже. Войти снова — через бота.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Остаться')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Выйти везде')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.post('/auth/logout?everywhere=true');
    } on ApiError catch (e) {
      _snack(e.message);
      return;
    }
    _leave();
  }

  Future<void> _link(String provider) async {
    tick();
    try {
      final r = await api.post('/auth/$provider/link', {'client': 'app'});
      final url = Uri.parse(r['url'] as String);
      final open = widget.open ?? (u) => launchUrl(u, mode: LaunchMode.externalApplication);
      await open(url);
    } on ApiError catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _unlink(String provider) async {
    tick();
    try {
      await api.delete('/auth/identities/$provider');
    } on ApiError catch (e) {
      _snack(e.message);
      return;
    }
    setState(() => _epoch++);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Backdrop(
      child: SafeArea(
        child: Loader<_Data>(
          key: ValueKey(_epoch),
          load: _load,
          onUnauthorized: widget.onUnauthorized,
          builder: (context, d, _) {
            final s = AppStyle.of(context);
            final p = s.p;
            final ids = d.identities;
            final available = (ids?['available'] as List?) ?? const [];
            final linked = {for (final i in (ids?['items'] as List?) ?? const []) i['provider']};
            return ListView(
              padding: const EdgeInsets.only(bottom: Space.xxl),
              children: [
                const BackRow(),
                const ScreenTitle(eyebrow: 'что бот знает и как это защищено', title: 'Безопасность'),
                const Section('Устройства'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.l),
                  child: Tile(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        for (var i = 0; i < d.sessions.length; i++) ...[
                          if (i > 0) Divider(height: 1, color: p.line),
                          _ActionRow(
                            icon: Icons.smartphone_outlined,
                            title:
                                '${d.sessions[i]['device'] ?? 'Устройство'}'
                                '${d.sessions[i]['current'] == true ? ' · это' : ''}',
                            sub: 'заходил ${_seen(d.sessions[i]['last_seen'] as String?)}',
                            action: 'Выйти',
                            danger: true,
                            onTap: () => _revoke(d.sessions[i] as Map),
                          ),
                        ],
                        if (d.sessions.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(Space.l),
                            child: Text('Входов вне Telegram нет', style: s.body(14, color: p.muted)),
                          ),
                      ],
                    ),
                  ),
                ),
                if (d.sessions.length > 1)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                    child: TextButton.icon(
                      onPressed: _everywhere,
                      icon: Icon(Icons.logout_rounded, color: p.danger, size: 18),
                      label: Text(
                        'Выйти везде',
                        style: s.body(15, weight: FontWeight.w600, color: p.danger),
                      ),
                    ),
                  ),
                if (available.isNotEmpty) ...[
                  const Section('Вход без Telegram'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.s),
                    child: Text(
                      'Привяжи VK или Яндекс — войдёшь, даже если Telegram не откроется.',
                      style: s.body(13, color: p.muted),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.l),
                    child: Tile(
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < available.length; i++) ...[
                            if (i > 0) Divider(height: 1, color: p.line),
                            linked.contains(available[i]['id'])
                                ? _ActionRow(
                                    icon: Icons.link_rounded,
                                    title: available[i]['name'] as String,
                                    sub: 'привязан',
                                    action: 'Отвязать',
                                    danger: true,
                                    onTap: () => _unlink(available[i]['id'] as String),
                                  )
                                : _ActionRow(
                                    icon: Icons.add_link_rounded,
                                    title: available[i]['name'] as String,
                                    sub: 'не привязан',
                                    action: 'Привязать',
                                    onTap: () => _link(available[i]['id'] as String),
                                  ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
                const Section('Как защищены данные'),
                for (final (icon, title, text) in _facts(d.security))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
                    child: Tile(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(icon, color: p.accent, size: 22),
                          const SizedBox(width: Space.m),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title, style: s.body(15, weight: FontWeight.w600)),
                                const SizedBox(height: 2),
                                Text(text, style: s.body(13, color: p.muted)),
                              ],
                            ),
                          ),
                        ],
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

/// «сегодня», «вчера», «8 октября» — время с сервера в UTC.
String _seen(String? at) {
  final t = at == null ? null : DateTime.tryParse('${at.replaceFirst(' ', 'T')}Z')?.toLocal();
  if (t == null) return 'давно';
  final today = now();
  final days = DateTime(today.year, today.month, today.day).difference(DateTime(t.year, t.month, t.day)).inDays;
  if (days <= 0) return 'сегодня';
  if (days == 1) return 'вчера';
  return '${t.day} ${monthsGen[t.month - 1]}';
}

/// Коротко о защите — смысл как в листе WebApp, цифры с сервера.
List<(IconData, String, String)> _facts(Map s) {
  final key =
      {
        'passphrase': 'из секретной фразы старосты',
        'key': 'отдельный ключ старосты',
        'bot_token': 'производный от ключа бота',
      }[s['key_source']] ??
      'в настройках сервера';
  final lim = (s['limits'] as Map?) ?? const {};
  final ai = (lim['ai'] as Map?)?['count'] ?? 15;
  final sub = (lim['submit'] as Map?) ?? const {};
  return [
    (
      Icons.lock_outline_rounded,
      'Вход в СДО зашифрован',
      '${s['sdo'] == 'ok' ? 'Твой вход подключён. ' : ''}Хранится не пароль, а только «оставаться в системе» — '
          'зашифрованным (Fernet). Ключ — $key, отдельно от базы.',
    ),
    (
      Icons.phonelink_lock_outlined,
      'Вход в приложение',
      'Через бота: на телефоне — ключ этого устройства, на сервере — только его отпечаток. Выйти — выше.',
    ),
    (
      Icons.download_outlined,
      'Файлы — по коротким ссылкам',
      'Ссылка на скачивание подписана и живёт ${s['link_minutes'] ?? 10} минут.',
    ),
    (
      Icons.auto_awesome_outlined,
      'ИИ (Gemini от Google)',
      'Уходит только вопрос, история чата и нужные куски лекций. Имя и вход в СДО — нет. Личное туда не пиши.',
    ),
    (
      Icons.insights_outlined,
      'Статистика — без содержимого',
      'Только «кто, что открыл и когда». Через ${s['events_days'] ?? 180} дней удаляется сама.',
    ),
    (
      Icons.speed_outlined,
      'Защита от перегруза',
      'Не больше $ai вопросов ИИ в минуту и ${sub['count'] ?? 6} сдач за ${sub['minutes'] ?? 10} минут.',
    ),
  ];
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String title, sub, action;
  final bool danger;
  final VoidCallback onTap;
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.sub,
    required this.action,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.s, Space.s),
      child: Row(
        children: [
          Icon(icon, color: p.muted, size: 20),
          const SizedBox(width: Space.m),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: s.body(15, weight: FontWeight.w600)),
                Text(sub, style: s.body(12, color: p.muted)),
              ],
            ),
          ),
          TextButton(
            onPressed: onTap,
            child: Text(
              action,
              style: s.body(14, weight: FontWeight.w600, color: danger ? p.danger : p.accent),
            ),
          ),
        ],
      ),
    );
  }
}
