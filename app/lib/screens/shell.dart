// Оболочка: пять вкладок и меню-капсула; при первом запуске — короткое
// знакомство «что где».
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api.dart';
import '../api/models.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/capsule_tabbar.dart';
import '../widgets/common.dart';
import 'deadlines.dart';
import 'group_pick.dart';
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
  'баллы в среднем, настройки, шрифт, группа и выход',
];

class Shell extends StatefulWidget {
  final Api api;
  final ValueChanged<FontChoice> onFont;
  final ValueChanged<ThemeChoice>? onTheme;
  final VoidCallback onLogout, onUnauthorized;
  final int initialTab;
  const Shell({
    super.key,
    required this.api,
    required this.onFont,
    this.onTheme,
    required this.onLogout,
    required this.onUnauthorized,
    this.initialTab = 0,
  });

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  late int _index = widget.initialTab;

  /// Сменилась группа — номер растёт, экраны строятся заново со своими данными.
  int _epoch = 0;

  // СДО подключили из «Ещё» — «Учёба» строится заново
  int _sdo = 0;

  /// Сменили шрифт или тему, пока вкладка была скрыта: на iPhone такая
  /// вкладка оставалась со старым шрифтом (Onest не уходил обратно, владелец
  /// 09.10, 3.7). Скрытые вкладки строятся заново, когда их открывают.
  final _gen = List<int>.filled(tabs.length, 0);
  final _stale = <int>{};
  (FontChoice, bool)? _style;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = AppStyle.of(context);
    final cur = (s.font, s.p.dark);
    if (_style != null && _style != cur) {
      for (var i = 0; i < tabs.length; i++) {
        if (i != _index) _stale.add(i);
      }
    }
    _style = cur;
  }

  void _open(int i) => setState(() {
    if (_stale.remove(i)) _gen[i]++;
    _index = i;
  });

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _ensureGroup();
      await _maybeTour();
    });
  }

  /// Нет группы в профиле (новый человек) — сначала выбрать её.
  Future<void> _ensureGroup() async {
    Map? me;
    try {
      me = await widget.api.get('/me') as Map?;
    } catch (_) {
      return; // нет сети или вход устарел — экраны сами скажут
    }
    if (me == null || me['group'] != null || !mounted) return;
    await pickGroup(required: true);
  }

  Future<void> pickGroup({bool required = false}) async {
    final g = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(
        builder: (_) => GroupPickScreen(api: widget.api, required: required),
      ),
    );
    if (g != null && mounted) setState(() => _epoch++);
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
    final g = _gen;
    final pages = [
      TodayScreen(key: ValueKey('today$_epoch.${g[0]}'), api: api, onUnauthorized: un),
      WeekScreen(key: ValueKey('week$_epoch.${g[1]}'), api: api, onUnauthorized: un),
      DeadlinesScreen(key: ValueKey('dl$_epoch.${g[2]}'), api: api, onUnauthorized: un),
      StudyScreen(key: ValueKey('study$_epoch.$_sdo.${g[3]}'), api: api, onUnauthorized: un),
      MoreScreen(
        key: ValueKey('more$_epoch.${g[4]}'),
        api: api,
        onFont: widget.onFont,
        onTheme: widget.onTheme,
        onLogout: widget.onLogout,
        onUnauthorized: un,
        onGroup: () => pickGroup(),
        onStudy: () => _open(tabByName('study')),
        onSdo: () => setState(() => _sdo++),
      ),
    ];
    return Scaffold(
      extendBody: true,
      body: Backdrop(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              OfflineBanner(since: widget.api.offlineSince),
              Expanded(
                child: IndexedStack(index: _index, children: pages),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: CapsuleTabBar(items: tabs, index: _index, onTap: _open),
    );
  }
}

/// «Без сети · данные от 10:07» — пока ответы идут из памяти телефона.
class OfflineBanner extends StatelessWidget {
  final ValueListenable<DateTime?> since;
  const OfflineBanner({super.key, required this.since});

  static String label(DateTime at, DateTime today) {
    final hm = '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final days = DateTime(today.year, today.month, today.day).difference(DateTime(at.year, at.month, at.day)).inDays;
    final day = switch (days) {
      0 => '',
      1 => 'вчера ',
      _ => '${at.day} ${monthsGen[at.month - 1]} ',
    };
    return 'Без сети · данные от $day$hm';
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    return ValueListenableBuilder<DateTime?>(
      valueListenable: since,
      builder: (context, at, _) => AnimatedSize(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        child: at == null
            ? const SizedBox(width: double.infinity)
            : Padding(
                padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, 0),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: Space.l, vertical: Space.s),
                  decoration: BoxDecoration(
                    color: s.p.warn.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.cloud_off_rounded, size: 16, color: s.p.warn),
                      const SizedBox(width: Space.s),
                      Expanded(
                        child: Text(label(at, now()), style: s.body(13, weight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
