import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:krom_bundler/src/backend/backend_client.dart';
import 'package:test/test.dart';

void main() {
  BackendClient clientWith(MockClient mock) =>
      BackendClient(baseUrl: 'http://localhost:8080/', token: 'krom_pat_x', httpClient: mock);

  String appsPage(List<Map<String, String>> items, {int totalPages = 1}) =>
      jsonEncode({'items': items, 'totalPages': totalPages, 'pageNumber': 0});

  group('findAppBySlug', () {
    test('returns the matching app', () async {
      final client = clientWith(MockClient((req) async {
        expect(req.method, 'GET');
        expect(req.url.path, '/api/v1/apps');
        expect(req.headers['Authorization'], 'Bearer krom_pat_x');
        return http.Response(
          appsPage([
            {'id': 'uuid-1', 'slug': 'other', 'name': 'Other'},
            {'id': 'uuid-2', 'slug': 'wallet', 'name': 'Wallet'},
          ]),
          200,
        );
      }));

      final app = await client.findAppBySlug('wallet');
      expect(app, isNotNull);
      expect(app!.id, 'uuid-2');
      expect(app.name, 'Wallet');
    });

    test('returns null when no page contains the slug', () async {
      final client = clientWith(MockClient(
        (req) async => http.Response(appsPage(const []), 200),
      ));
      expect(await client.findAppBySlug('nope'), isNull);
    });

    test('pages through until it finds the slug', () async {
      final client = clientWith(MockClient((req) async {
        final page = int.parse(req.url.queryParameters['page'] ?? '0');
        if (page == 0) {
          return http.Response(
            appsPage([
              {'id': 'a', 'slug': 'x', 'name': 'X'}
            ], totalPages: 2),
            200,
          );
        }
        return http.Response(
          appsPage([
            {'id': 'b', 'slug': 'target', 'name': 'T'}
          ], totalPages: 2),
          200,
        );
      }));

      final app = await client.findAppBySlug('target');
      expect(app?.id, 'b');
    });
  });

  group('ensureApp', () {
    test('creates the app when the slug is unknown', () async {
      var created = false;
      final client = clientWith(MockClient((req) async {
        if (req.method == 'GET') {
          return http.Response(appsPage(const []), 200);
        }
        // POST /api/v1/apps
        created = true;
        expect(req.url.path, '/api/v1/apps');
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['slug'], 'newapp');
        expect(body['name'], 'New App');
        return http.Response(
          jsonEncode({'id': 'fresh-uuid', 'slug': 'newapp', 'name': 'New App'}),
          201,
        );
      }));

      final app = await client.ensureApp(slug: 'newapp', name: 'New App');
      expect(created, isTrue);
      expect(app.id, 'fresh-uuid');
    });

    test('reuses the existing app without creating', () async {
      final client = clientWith(MockClient((req) async {
        if (req.method == 'POST') fail('should not create an existing app');
        return http.Response(
          appsPage([
            {'id': 'existing', 'slug': 'wallet', 'name': 'Wallet'}
          ]),
          200,
        );
      }));

      final app = await client.ensureApp(slug: 'wallet', name: 'Wallet');
      expect(app.id, 'existing');
    });
  });

  group('deployPackage', () {
    test('uploads a multipart version and returns the created version', () async {
      final client = clientWith(MockClient((req) async {
        expect(req.method, 'POST');
        expect(req.url.path, '/api/v1/apps/uuid-2/versions');
        expect(req.headers['content-type'], contains('multipart/form-data'));
        return http.Response(
          jsonEncode(
              {'id': 'ver-1', 'versionString': '1.0.0', 'status': 'DRAFT'}),
          200,
        );
      }));

      final v = await client.deployPackage(
        appId: 'uuid-2',
        version: '1.0.0',
        zipBytes: [1, 2, 3],
        filename: 'wallet__1.0.0.zip',
      );
      expect(v.id, 'ver-1');
      expect(v.version, '1.0.0');
      expect(v.status, 'DRAFT');
    });

    test('throws on a 409 version conflict', () async {
      final client = clientWith(
        MockClient((req) async => http.Response('conflict', 409)),
      );
      expect(
        () => client.deployPackage(
            appId: 'a', version: '1.0.0', zipBytes: [0], filename: 'a.zip'),
        throwsA(isA<BackendException>()
            .having((e) => e.statusCode, 'statusCode', 409)),
      );
    });
  });

  group('bind', () {
    test('posts appId + superAppId', () async {
      Map<String, dynamic>? sent;
      final client = clientWith(MockClient((req) async {
        expect(req.url.path, '/api/v1/bindings');
        sent = jsonDecode(req.body) as Map<String, dynamic>;
        return http.Response('{}', 200);
      }));

      await client.bind(appId: 'app-1', superAppId: 'super-1');
      expect(sent, {'appId': 'app-1', 'superAppId': 'super-1'});
    });

    test('throws on failure', () async {
      final client = clientWith(
        MockClient((req) async => http.Response('forbidden', 403)),
      );
      expect(() => client.bind(appId: 'a', superAppId: 's'),
          throwsA(isA<BackendException>()));
    });
  });

  group('submitForReview', () {
    test('posts to the submit endpoint', () async {
      Uri? seen;
      final client = clientWith(MockClient((req) async {
        seen = req.url;
        return http.Response('{}', 200);
      }));

      await client.submitForReview(appId: 'app-1', versionId: 'ver-1');
      expect(seen!.path, '/api/v1/apps/app-1/versions/ver-1/submit');
    });
  });
}
