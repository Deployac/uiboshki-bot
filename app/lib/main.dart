// УИБО — своё приложение (этап 3). Тема — по теме телефона: тёмная
// «Глубина», светлая «Тетрадь»; шрифт — настройка в «Ещё».
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api/api.dart';
import 'screens/login.dart';
import 'screens/shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final api = Api();
  await api.load();
  final prefs = await SharedPreferences.getInstance();
  final font = prefs.getString('uib_font') == 'strict' ? FontChoice.strict : FontChoice.book;
  runApp(UiboApp(api: api, font: font));
}

class UiboApp extends StatefulWidget {
  final Api api;
  final FontChoice font;
  const UiboApp({super.key, required this.api, this.font = FontChoice.book});

  @override
  State<UiboApp> createState() => _UiboAppState();
}

class _UiboAppState extends State<UiboApp> {
  late FontChoice _font = widget.font;
  late bool _loggedIn = widget.api.token != null;

  Future<void> _setFont(FontChoice f) async {
    setState(() => _font = f);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('uib_font', f == FontChoice.strict ? 'strict' : 'book');
  }

  Future<void> _logout() async {
    await widget.api.logout();
    if (mounted) setState(() => _loggedIn = false);
  }

  @override
  Widget build(BuildContext context) {
    final dark = MediaQuery.platformBrightnessOf(context) == Brightness.dark;
    final p = dark ? Palette.depth : Palette.notebook;
    SystemChrome.setSystemUIOverlayStyle(dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark);
    return AppStyle(
      p: p,
      font: _font,
      child: MaterialApp(
        title: 'УИБО',
        debugShowCheckedModeBanner: false,
        theme: materialTheme(p),
        home: _loggedIn
            ? Shell(
                api: widget.api,
                onFont: _setFont,
                onLogout: _logout,
                onUnauthorized: _logout,
                initialTab: tabByName(Uri.base.queryParameters['tab']),
              )
            : LoginScreen(api: widget.api, onDone: () => setState(() => _loggedIn = true)),
      ),
    );
  }
}
