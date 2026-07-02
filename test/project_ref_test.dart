import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:krom_bundler/src/backend/backend_client.dart';
import 'package:krom_bundler/src/backend/project_ref.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _uuid = '3f2b1a90-1234-4abc-9def-0123456789ab';
const _otherUuid = '99999999-9999-4999-8999-999999999999';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('project_ref_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String writeManifest(Map<String, dynamic> json) {
    final path = p.join(tmp.path, 'manifest.json');
    File(path).writeAsStringSync(jsonEncode(json));
    return path;
  }

  BackendClient clientWith(MockClient mock) => BackendClient(
      baseUrl: 'http://localhost:8080', token: 'krom_pat_x', httpClient: mock);

  group('ManifestRef', () {
    test('exposes slug/appId/name/version, rejecting a non-UUID appId', () {
      final ref = ManifestRef.load(writeManifest({
        'id': 'wallet',
        'appId': 'not-a-uuid',
        'name': 'Wallet',
        'version': '1.2.0',
      }));
      expect(ref.slug, 'wallet');
      expect(ref.appId, isNull);
      expect(ref.name, 'Wallet');
      expect(ref.version, '1.2.0');
    });

    test('writeAppId inserts right after "id", preserving key order', () {
      final path = writeManifest({
        'id': 'wallet',
        'name': 'Wallet',
        'version': '1.0.0',
        'entry': 'home',
      });
      ManifestRef.load(path).writeAppId(_uuid);

      final raw = File(path).readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded.keys.toList(),
          ['id', 'appId', 'name', 'version', 'entry']);
      expect(decoded['appId'], _uuid);
      expect(ManifestRef.load(path).appId, _uuid);
    });

    test('writeAppId updates an existing appId in place', () {
      final path = writeManifest({
        'id': 'wallet',
        'appId': _otherUuid,
        'name': 'Wallet',
      });
      ManifestRef.load(path).writeAppId(_uuid);
      final decoded =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      expect(decoded.keys.toList(), ['id', 'appId', 'name']);
      expect(decoded['appId'], _uuid);
    });
  });

  group('version bump', () {
    test('bumpPatch increments the patch and drops suffixes', () {
      expect(ManifestRef.bumpPatch('1.2.3'), '1.2.4');
      expect(ManifestRef.bumpPatch('0.0.9'), '0.0.10');
      expect(ManifestRef.bumpPatch('2.0.0-beta+42'), '2.0.1');
      expect(ManifestRef.bumpPatch('abc'), isNull);
      expect(ManifestRef.bumpPatch('1.2'), isNull);
    });

    test('writeVersion rewrites in place, preserving key order', () {
      final path = writeManifest({
        'id': 'wallet',
        'appId': _uuid,
        'name': 'Wallet',
        'version': '1.0.0',
      });
      ManifestRef.load(path).writeVersion('1.0.1');
      final decoded =
          jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      expect(decoded.keys.toList(), ['id', 'appId', 'name', 'version']);
      expect(decoded['version'], '1.0.1');
      expect(ManifestRef.load(path).version, '1.0.1');
    });
  });

  group('resolveProjectApp', () {
    test('trusts a valid manifest appId (single GET, no slug lookup)', () async {
      final paths = <String>[];
      final client = clientWith(MockClient((req) async {
        paths.add(req.url.path);
        return http.Response(
            jsonEncode({'id': _uuid, 'slug': 'wallet', 'name': 'Wallet'}),
            200);
      }));
      final manifest = ManifestRef.load(
          writeManifest({'id': 'wallet', 'appId': _uuid, 'name': 'Wallet'}));

      final app =
          await resolveProjectApp(client: client, manifest: manifest);
      expect(app?.id, _uuid);
      expect(paths, ['/api/v1/apps/$_uuid']);
    });

    test('heals a stale appId via the slug and rewrites the manifest',
        () async {
      final client = clientWith(MockClient((req) async {
        if (req.url.path == '/api/v1/apps/$_otherUuid') {
          return http.Response('not found', 404); // stale id (other backend)
        }
        // Slug listing finds the real app.
        return http.Response(
          jsonEncode({
            'items': [
              {'id': _uuid, 'slug': 'wallet', 'name': 'Wallet'},
            ],
            'totalPages': 1,
          }),
          200,
        );
      }));
      final path = writeManifest(
          {'id': 'wallet', 'appId': _otherUuid, 'name': 'Wallet'});
      final manifest = ManifestRef.load(path);

      final app =
          await resolveProjectApp(client: client, manifest: manifest);
      expect(app?.id, _uuid);
      expect(ManifestRef.load(path).appId, _uuid, reason: 'self-healed');
    });

    test('creates by slug when unlinked and writes the appId back', () async {
      final client = clientWith(MockClient((req) async {
        if (req.method == 'GET') {
          return http.Response(
              jsonEncode({'items': [], 'totalPages': 1}), 200);
        }
        final body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(body['slug'], 'wallet');
        return http.Response(
            jsonEncode({'id': _uuid, 'slug': 'wallet', 'name': 'Wallet'}),
            201);
      }));
      final path = writeManifest({'id': 'wallet', 'name': 'Wallet'});

      final app = await resolveProjectApp(
          client: client, manifest: ManifestRef.load(path));
      expect(app?.id, _uuid);
      expect(ManifestRef.load(path).appId, _uuid);
    });

    test('returns null (and leaves the manifest alone) when not found and '
        'createIfMissing is false', () async {
      final client = clientWith(MockClient((req) async => http.Response(
          jsonEncode({'items': [], 'totalPages': 1}), 200)));
      final path = writeManifest({'id': 'wallet', 'name': 'Wallet'});

      final app = await resolveProjectApp(
        client: client,
        manifest: ManifestRef.load(path),
        createIfMissing: false,
      );
      expect(app, isNull);
      expect(ManifestRef.load(path).appId, isNull);
    });
  });
}
