// Вход: код → ссылка в бота → «Да, это я» в Telegram → приложение получает
// токен сессии устройства (тот же путь, что у PWA, этап 2). Или VK ID /
// Яндекс ID: окно входа провайдера, назад — ru.uiboshki.app://auth#token=…
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api/api.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/capy.dart';
import '../widgets/common.dart';

/// Окно входа провайдера → адрес возврата (в тестах подменяется).
typedef WebAuth = Future<String> Function(String url);

Future<String> systemWebAuth(String url) =>
    FlutterWebAuth2.authenticate(url: url, callbackUrlScheme: 'ru.uiboshki.app');

class LoginScreen extends StatefulWidget {
  final Api api;
  final VoidCallback onDone;
  final WebAuth webAuth;
  const LoginScreen({super.key, required this.api, required this.onDone, this.webAuth = systemWebAuth});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  Timer? _poll;
  String? _code, _link, _note;
  bool _busy = false;
  List<({String id, String name})> _providers = [];

  @override
  void initState() {
    super.initState();
    widget.api
        .providers()
        .then((p) {
          if (mounted) setState(() => _providers = p);
        })
        .catchError((_) {});
  }

  Future<void> _oauth(String provider) async {
    tick();
    try {
      final back = await widget.webAuth(await widget.api.startOAuth(provider));
      if (await widget.api.finishOAuth(back) != null) {
        widget.onDone();
      } else {
        setState(() => _note = 'Вход не завершён — попробуй ещё раз.');
      }
    } catch (_) {
      if (mounted) setState(() => _note = 'Вход отменён.');
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    tick();
    setState(() {
      _busy = true;
      _note = null;
    });
    try {
      final r = await widget.api.startLogin();
      _code = r.code;
      _link = r.link;
      await launchUrl(Uri.parse(r.link), mode: LaunchMode.externalApplication);
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) => _check());
      setState(() => _note = 'Подтверди вход в боте — «Да, это я»');
    } catch (e) {
      setState(() {
        _busy = false;
        _note = 'Не получилось: $e';
      });
    }
  }

  Future<void> _check() async {
    final code = _code;
    if (code == null) return;
    try {
      final status = await widget.api.pollLogin(code);
      if (status == null) return;
      _poll?.cancel();
      if (status == 'ok') {
        widget.onDone();
        return;
      }
      setState(() {
        _busy = false;
        _code = null;
        _note = status == 'denied' ? 'Вход отклонён в боте.' : 'Код устарел — попробуй ещё раз.';
      });
    } catch (_) {
      /* сеть моргнула — спросим ещё раз через 2 с */
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = AppStyle.of(context);
    final p = s.p;
    return Scaffold(
      body: Backdrop(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(Space.xl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Spacer(),
                CapyImage(pose: CapyPose.splash, size: 120, color: p.accent),
                const SizedBox(height: Space.xl),
                Text('учёба МИРЭА · расписание · сроки · баллы', style: s.eyebrow()),
                const SizedBox(height: 6),
                Text('Капибара', style: s.title(54)),
                const SizedBox(height: 10),
                Container(
                  width: 34,
                  height: 3,
                  decoration: BoxDecoration(color: p.accent, borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: Space.l),
                Text(
                  'Без паролей и кодов из SMS: через бота в Telegram, VK или Яндекс.',
                  style: s.body(16, color: p.muted),
                ),
                const Spacer(),
                if (_note != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: Space.m),
                    child: Text(_note!, style: s.body(14, color: p.muted)),
                  ),
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: p.accent,
                      foregroundColor: p.onAccent,
                      shape: const StadiumBorder(),
                      textStyle: s.body(16, weight: FontWeight.w700),
                    ),
                    onPressed: _busy && _link == null ? null : (_busy ? () => launchUrl(Uri.parse(_link!)) : _start),
                    child: Text(_busy ? 'Открыть бота ещё раз' : 'Войти через Telegram'),
                  ),
                ),
                for (final pr in _providers) ...[
                  const SizedBox(height: Space.s),
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: p.text,
                        side: BorderSide(color: p.line),
                        shape: const StadiumBorder(),
                        textStyle: s.body(15, weight: FontWeight.w600),
                      ),
                      onPressed: () => _oauth(pr.id),
                      child: Text('Войти через ${pr.name}'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
