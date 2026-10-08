// Клиент API бота (/api/v1, этап 2): вход через бота, токен сессии устройства.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
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

  /// Без сети — ответы GET из последней удачной загрузки (как sw.js у PWA).
  /// Время той загрузки — здесь; null — данные свежие.
  final offlineSince = ValueNotifier<DateTime?>(null);
  static const _cachePrefix = 'uib_cache:';
  static const timeout = Duration(seconds: 8);

  Future<dynamic> get(String path) async {
    final http.Response r;
    try {
      r = await _client.get(_uri(path), headers: _headers).timeout(timeout);
    } catch (e) {
      final cached = await _cached(path).catchError((_) => null);
      if (cached == null) rethrow;
      offlineSince.value = cached.at;
      return cached.body;
    }
    final body = _decode(r);
    offlineSince.value = null;
    // Запас — в фоне: показ данных не ждёт памяти телефона и не падает из-за неё.
    if (!path.startsWith('/auth/')) unawaited(_remember(path, r).catchError((_) {}));
    return body;
  }

  Future<void> _remember(String path, http.Response r) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      '$_cachePrefix$path',
      jsonEncode({'at': DateTime.now().toIso8601String(), 'body': utf8.decode(r.bodyBytes)}),
    );
  }

  Future<({DateTime at, dynamic body})?> _cached(String path) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('$_cachePrefix$path');
    if (raw == null) return null;
    final j = jsonDecode(raw);
    return (at: DateTime.parse(j['at'] as String), body: jsonDecode(j['body'] as String));
  }

  /// Выход — данные с телефона стираются (как «выйти» в PWA).
  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    for (final k in prefs.getKeys().where((k) => k.startsWith(_cachePrefix)).toList()) {
      await prefs.remove(k);
    }
    offlineSince.value = null;
  }

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

  // ── вход через VK ID / Яндекс ID (webapp/routes/auth.py) ──
  /// Какие входы кроме Telegram есть на сервере: [(id, название)].
  Future<List<({String id, String name})>> providers() async {
    final r = await get('/auth/providers');
    return [for (final p in r['items'] as List) (id: p['id'] as String, name: p['name'] as String)];
  }

  /// Ссылка на вход у провайдера; вернётся он на ru.uiboshki.app://auth#token=…
  Future<String> startOAuth(String provider) async =>
      (await post('/auth/$provider/start', {'client': 'app'}))['url'] as String;

  /// Адрес возврата → токен (сохраняется); null — токена нет.
  Future<String?> finishOAuth(String callbackUrl) async {
    final frag = Uri.parse(callbackUrl).fragment;
    if (!frag.startsWith('token=')) return null;
    final token = Uri.decodeComponent(frag.substring(6));
    await saveToken(token);
    return token;
  }

  Future<void> logout() async {
    try {
      await post('/auth/logout');
    } catch (_) {}
    await saveToken(null);
    await clearCache();
  }
}
