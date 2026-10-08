// «Ещё» — кто я и из какой группы, шрифт, тема, выход.
import 'package:flutter/material.dart';

import '../api/api.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

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
          const Section('Группа'),
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
