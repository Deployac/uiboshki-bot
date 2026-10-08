// Клиент API бота (/api/v1, этап 2): вход через бота, токен сессии устройства.
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class Unauthorized implements Exception {}

class ApiError implements Exception {
  final String message;
  ApiError(this.message);
  @override
  String toString() => message;
}

class Api {
  /// Адрес сервера; пустой — тот же сайт (сборка web со стенда).
  static const base = String.fromEnvironment('API', defaultValue: 'https://www.uiboshki.ru');
  static const _tokenKey = 'uib_token';

  String? token;
  final http.Client _client;

  Api({http.Client? client}) : _client = client ?? http.Client();

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    token = prefs.getString(_tokenKey);
  }

  Future<void> saveToken(String? value) async {
    token = value;
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, value);
    }
  }

  Uri _uri(String path) => Uri.parse('$base/api/v1$path');

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };

  dynamic _decode(http.Response r) {
    if (r.statusCode == 401) throw Unauthorized();
    final body = r.body.isEmpty ? null : jsonDecode(utf8.decode(r.bodyBytes));
    if (r.statusCode >= 400) {
      final detail = body is Map ? body['detail'] : null;
      throw ApiError(detail is String ? detail : 'ошибка сервера (${r.statusCode})');
    }
    return body;
  }

  Future<dynamic> get(String path) async => _decode(await _client.get(_uri(path), headers: _headers));

  Future<dynamic> post(String path, [Object? body]) async =>
      _decode(await _client.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})));

  // ── вход через бота: код → ссылка в бота → «Да, это я» → токен ──
  Future<({String code, String link})> startLogin() async {
    final r = await post('/auth/start');
    return (code: r['code'] as String, link: r['link'] as String);
  }

  /// null — ещё ждём; иначе статус: ok / denied / expired.
  Future<String?> pollLogin(String code) async {
    final r = await post('/auth/poll', {'code': code});
    final status = r['status'] as String;
    if (status == 'ok') await saveToken(r['token'] as String);
    return status == 'wait' ? null : status;
  }

  Future<void> logout() async {
    try {
      await post('/auth/logout');
    } catch (_) {}
    await saveToken(null);
  }
}
