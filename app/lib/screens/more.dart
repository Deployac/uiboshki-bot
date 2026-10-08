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
  const MoreScreen({super.key, required this.api, required this.onFont, required this.onLogout, this.onUnauthorized});

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
          ScreenTitle(eyebrow: me['group']?['name'] ?? 'группа не выбрана', title: me['first_name'] ?? 'Ещё'),
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
