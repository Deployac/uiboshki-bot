// Ответы API из записи стенда сайта (webapp/static/site/demo.json) —
// те же, что видит демо на /about/demo; ничьих настоящих данных.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:uiboshki/api/api.dart';

Map<String, dynamic> demoFixtures() {
  final f = File('../webapp/static/site/demo.json');
  return Map<String, dynamic>.from(jsonDecode(f.readAsStringSync())['fx']);
}

/// Api, который отвечает записанными ответами; requests — что спрашивали.
Api fakeApi({String? token = 'test-token', List<String>? requests, Map<String, Object?>? bodies}) {
  final fx = demoFixtures();
  final client = MockClient((req) async {
    final path = req.url.path.replaceFirst('/api/v1/', '/api/');
    final q = req.url.query.isEmpty ? '' : '?${req.url.query}';
    var key = '${req.method} $path$q';
    if (path.startsWith('/api/sdo/goal/')) key += '|${jsonDecode(req.body)['label']}'; // как demo.js на сайте
    requests?.add(key);
    if (req.method == 'POST' && req.body.isNotEmpty) bodies?[key] = jsonDecode(req.body);
    if (req.headers['Authorization'] == null && !path.startsWith('/api/auth/')) {
      return http.Response('{"detail":"нет входа"}', 401);
    }
    Object? body = fx[key];
    body ??= switch (path) {
      '/api/day' => {'lessons': []},
      '/api/week' => {'week': null, 'days': []},
      '/api/auth/start' => {'code': 'abc', 'link': 'https://t.me/UiboshkiBot?start=login_abc'},
      '/api/auth/poll' => {'status': 'wait'},
      '/api/sdo/submit-rules' => {
        'accepted': ['.zip'],
        'labels': ['Архив ZIP'],
        'maxfiles': 2,
        'maxbytes': 10485760,
      },
      '/api/sdo/submit' => {'status': 'Отправлено для оценивания'},
      _ => {'ok': true},
    };
    return http.Response.bytes(utf8.encode(jsonEncode(body)), 200, headers: {'content-type': 'application/json'});
  });
  return Api(client: client)..token = token;
}
