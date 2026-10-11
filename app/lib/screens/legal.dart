// 152-ФЗ: согласие на обработку персональных данных и политика — как в
// WebApp (js/privacy.js). Тексты — /api/v1/legal/<имя> (legal_texts.py на
// сервере), рисуем сами, в дизайне приложения. Галочка по умолчанию не стоит,
// кнопка рядом неактивна, пока её нет; ссылки в подписи открывают текст
// поверх экрана — введённое не теряется.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../api/api.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'files.dart' show BackRow;

/// Ссылки в тексте — синим, как почти везде (Никита, 11.10).
extension LegalLink on Palette {
  Color get link => dark ? const Color(0xFF7FB0FF) : const Color(0xFF2F6FD6);
}

void openLegal(BuildContext context, Api api, String name) {
  tick();
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => LegalScreen(api: api, name: name)));
}

/// Текст согласия или политики.
class LegalScreen extends StatelessWidget {
  final Api api;
  final String name;
  const LegalScreen({super.key, required this.api, required this.name});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Backdrop(
      child: SafeArea(
        child: Loader<Map>(
          load: () async => await api.get('/legal/$name') as Map,
          builder: (context, d, _) {
            final s = AppStyle.of(context);
            final p = s.p;
            return ListView(
              padding: const EdgeInsets.only(bottom: Space.xxl),
              children: [
                const BackRow(),
                ScreenTitle(title: d['title'] as String, sub: 'Версия ${d['version']} от ${d['date']}'),
                Padding(
                  padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, 0),
                  child: Text(d['lead'] as String, style: s.body(15, color: p.muted)),
                ),
                for (final sec in (d['sections'] as List)) ...[
                  Section(sec['title'] as String),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.l),
                    child: Tile(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final b in (sec['blocks'] as List))
                            if (b['ul'] != null)
                              for (final item in (b['ul'] as List))
                                Padding(
                                  padding: const EdgeInsets.only(bottom: Space.s),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.only(top: 7, right: Space.m),
                                        child: Container(
                                          width: 5,
                                          height: 5,
                                          decoration: BoxDecoration(color: p.accent, shape: BoxShape.circle),
                                        ),
                                      ),
                                      Expanded(child: Text(item as String, style: s.body(14))),
                                    ],
                                  ),
                                )
                            else
                              Padding(
                                padding: const EdgeInsets.only(bottom: Space.s),
                                child: Text(b['p'] as String, style: s.body(14)),
                              ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// Галочка «Даю согласие на обработку персональных данных» и строка
/// «Подробнее — в Политике…»: названия документов — синие ссылки.
class ConsentCheck extends StatefulWidget {
  final Api api;
  final bool value;
  final ValueChanged<bool> onChanged;

  /// Хвост подписи: «, в том числе из СДО: …».
  final String extra;
  const ConsentCheck({super.key, required this.api, required this.value, required this.onChanged, this.extra = ''});

  @override
  State<ConsentCheck> createState() => _ConsentCheckState();
}

class _ConsentCheckState extends State<ConsentCheck> {
  late final _consent = TapGestureRecognizer()..onTap = () => openLegal(context, widget.api, 'consent');
  late final _policy = TapGestureRecognizer()..onTap = () => openLegal(context, widget.api, 'privacy');

  @override
  void dispose() {
    _consent.dispose();
    _policy.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    final on = widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          checked: on,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.chip),
            onTap: () {
              tick();
              widget.onChanged(!on);
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.s),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: on ? p.accent : Colors.transparent,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: on ? p.accent : p.muted, width: 2),
                    ),
                    child: on ? Icon(Icons.check_rounded, size: 16, color: p.onAccent) : null,
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: s.body(14),
                        children: [
                          const TextSpan(text: 'Даю '),
                          TextSpan(
                            text: 'согласие на обработку персональных данных',
                            style: TextStyle(color: p.link),
                            recognizer: _consent,
                          ),
                          TextSpan(text: widget.extra),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 34),
          child: Text.rich(
            TextSpan(
              style: s.body(12.5, color: p.muted),
              children: [
                const TextSpan(text: 'Подробнее — в '),
                TextSpan(
                  text: 'Политике обработки персональных данных',
                  style: TextStyle(color: p.link),
                  recognizer: _policy,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Первый вход (и новая версия текста): без согласия дальше нельзя —
/// «Продолжить» с галочкой или отказ с удалением данных. true — согласился.
class ConsentScreen extends StatefulWidget {
  final Api api;
  const ConsentScreen({super.key, required this.api});

  @override
  State<ConsentScreen> createState() => _ConsentScreenState();
}

class _ConsentScreenState extends State<ConsentScreen> {
  bool _agree = false, _busy = false;

  Future<void> _go() async {
    setState(() => _busy = true);
    try {
      await widget.api.post('/consent', {'kind': 'pd'});
    } on ApiError catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showToast(context, e.message, kind: ToastKind.error);
      }
      return;
    }
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _refuse() async {
    final ok = await confirmSheet(
      context,
      title: 'Без согласия — никак',
      text: 'Приложение не может хранить твои данные без согласия. Удалить то, что уже есть, и выйти?',
      action: 'Удалить и выйти',
      cancel: 'Назад',
      danger: true,
    );
    if (!ok || !mounted) return;
    final erased = await deleteMyData(context, widget.api, confirmed: true);
    if (erased && mounted) Navigator.pop(context, false);
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Backdrop(
          child: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(Space.l, Space.xxl, Space.l, Space.xxl),
              children: [
                Icon(Icons.verified_user_outlined, size: 44, color: p.accent),
                const SizedBox(height: Space.l),
                Text('Твои данные', style: s.title(30)),
                const SizedBox(height: Space.m),
                Text(
                  'Чтобы показывать расписание, дедлайны и баллы, приложению нужно хранить твой id, группу '
                  'и настройки. Что именно и сколько — в политике. Удалить всё можно в любой момент: '
                  '«Ещё → Безопасность».',
                  style: s.body(15, color: p.muted),
                ),
                const SizedBox(height: Space.l),
                ConsentCheck(api: widget.api, value: _agree, onChanged: (v) => setState(() => _agree = v)),
                const SizedBox(height: Space.xl),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.accent,
                      foregroundColor: p.onAccent,
                      shape: const StadiumBorder(),
                    ),
                    onPressed: _agree && !_busy ? _go : null,
                    child: const Text('Продолжить'),
                  ),
                ),
                const SizedBox(height: Space.s),
                TextButton(
                  onPressed: _busy ? null : _refuse,
                  child: Text('Не даю согласие', style: s.body(15, weight: FontWeight.w600, color: p.muted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// «Удалить все мои данные» (ст. 21): сразу и насовсем, с телефона тоже.
/// true — удалено (вход на этом устройстве уже недействителен).
Future<bool> deleteMyData(BuildContext context, Api api, {bool confirmed = false}) async {
  if (!confirmed) {
    final ok = await confirmSheet(
      context,
      title: 'Удалить все твои данные?',
      text: 'Профиль, группу, вход в СДО, историю баллов и посещений, личные дедлайны, устройства, '
          'входы через VK и Яндекс. Отменить нельзя.',
      action: 'Удалить всё',
      cancel: 'Оставить',
      danger: true,
    );
    if (!ok) return false;
  }
  try {
    await api.post('/me/delete', {'confirm': true});
  } on ApiError catch (e) {
    if (context.mounted) showToast(context, e.message, kind: ToastKind.error);
    return false;
  }
  await api.saveToken(null);
  await api.clearCache();
  if (context.mounted) showToast(context, 'Готово: всё о тебе удалено', kind: ToastKind.done);
  return true;
}
