// Оболочка: пять вкладок и меню-капсула; при первом запуске — короткое
// знакомство «что где».
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/capsule_tabbar.dart';
import '../widgets/common.dart';
import 'deadlines.dart';
import 'more.dart';
import 'study.dart';
import 'today.dart';
import 'week.dart';

const tabs = [
  TabItem(Icons.schedule_rounded, 'Сегодня'),
  TabItem(Icons.calendar_today_rounded, 'Неделя'),
  TabItem(Icons.bookmark_border_rounded, 'Сдать'),
  TabItem(Icons.school_outlined, 'Учёба'),
  TabItem(Icons.more_horiz_rounded, 'Ещё'),
];

/// Вкладка по имени из ссылки пуша (`/app?tab=deadlines`, delivery.py).
int tabByName(String? name) => switch (name) {
  'week' => 1,
  'deadlines' => 2,
  'sdo' || 'study' => 3,
  'more' => 4,
  _ => 0,
};

const _tour = [
  'пары сегодня: что идёт, сколько осталось, куда дальше',
  'вся неделя лентой, сверху — дни: нажми, и лента приедет',
  'что сдать и до какого срока, отметка «сдал»',
  'баллы, цель по предмету, посещения',
  'настройки, шрифт, группа и выход',
];

class Shell extends StatefulWidget {
  final Api api;
  final ValueChanged<FontChoice> onFont;
  final VoidCallback onLogout, onUnauthorized;
  final int initialTab;
  const Shell({
    super.key,
    required this.api,
    required this.onFont,
    required this.onLogout,
    required this.onUnauthorized,
    this.initialTab = 0,
  });

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late int _index = widget.initialTab;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeTour());
  }

  Future<void> _maybeTour() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('uib_toured') == true || !mounted) return;
    await prefs.setBool('uib_toured', true);
    if (!mounted) return;
    final s = AppStyle.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: s.p.cardSolid,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, Space.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Что где', style: s.title(28)),
              const SizedBox(height: Space.l),
              for (var i = 0; i < tabs.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: Space.m),
                  child: Row(
                    children: [
                      Icon(tabs[i].icon, color: s.p.accent),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: '${tabs[i].label} — ',
                                style: s.body(15, weight: FontWeight.w600),
                              ),
                              TextSpan(
                                text: _tour[i],
                                style: s.body(15, color: s.p.muted),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: Space.s),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: s.p.accent, foregroundColor: s.p.onAccent),
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Понятно'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final api = widget.api;
    final un = widget.onUnauthorized;
    final pages = [
      TodayScreen(api: api, onUnauthorized: un),
      WeekScreen(api: api, onUnauthorized: un),
      DeadlinesScreen(api: api, onUnauthorized: un),
      StudyScreen(api: api, onUnauthorized: un),
      MoreScreen(api: api, onFont: widget.onFont, onLogout: widget.onLogout, onUnauthorized: un),
    ];
    return Scaffold(
      extendBody: true,
      body: Backdrop(
        child: SafeArea(
          bottom: false,
          child: IndexedStack(index: _index, children: pages),
        ),
      ),
      bottomNavigationBar: CapsuleTabBar(items: tabs, index: _index, onTap: (i) => setState(() => _index = i)),
    );
  }
}
