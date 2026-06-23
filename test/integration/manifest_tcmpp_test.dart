import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:krom_bundler/src/bundler/manifest_bundler.dart';
import 'package:krom_bundler/src/bundler/bundler.dart';
import 'package:path/path.dart' as p;

void main() {
  group('ManifestBundler TCMPP integration', () {
    final tempDir = Directory('test_temp_tcmpp');

    setUp(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
      await tempDir.create();
      // A trivial valid page used by every test.
      await File(p.join(tempDir.path, 'home.ks')).writeAsString('''
fn build() {
  return Text("hi")
}
''');
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<String> writeManifest(Map<String, dynamic> m) async {
      final f = File(p.join(tempDir.path, 'manifest.json'));
      await f.writeAsString(jsonEncode(m));
      return f.path;
    }

    test('passes through window, tabBar, networkTimeout, scopes, subpackages',
        () async {
      // A second page used by the subpackage.
      await File(p.join(tempDir.path, 'detail.ks')).writeAsString('''
fn build() {
  return Text("detail")
}
''');
      final path = await writeManifest({
        'id': 'app',
        'name': 'App',
        'version': '1.0.0',
        'entry': 'home',
        'pages': {
          'home': {'name': 'Home', 'source': 'home.ks'},
          'detail': {'name': 'Detail', 'source': 'detail.ks'},
        },
        'window': {'navigationBarTitleText': 'App'},
        'tabBar': {
          'list': [
            {'pagePath': 'home', 'text': 'Home'},
            {'pagePath': 'home', 'text': 'Again'},
          ],
        },
        'scopes': {
          'scope.userLocation': {'desc': 'reason'},
        },
        'networkTimeout': {'request': 5000},
        'subpackages': [
          {
            'root': 'pkg',
            'pages': ['detail'],
          },
        ],
      });

      final bundler = ManifestBundler();
      final outJson = await bundler.bundleProject(path);
      final out = jsonDecode(outJson) as Map<String, dynamic>;

      expect(out['window'], isNotNull);
      expect(out['tabBar'], isNotNull);
      expect(out['scopes'], isNotNull);
      expect(out['networkTimeout'], isNotNull);
      expect(out['subpackages'], isNotNull);
    });

    test('rejects a manifest with an invalid tabBar pagePath', () async {
      final path = await writeManifest({
        'id': 'app',
        'name': 'App',
        'version': '1.0.0',
        'entry': 'home',
        'pages': {
          'home': {'name': 'Home', 'source': 'home.ks'},
        },
        'tabBar': {
          'list': [
            {'pagePath': 'home', 'text': 'Home'},
            {'pagePath': 'does_not_exist', 'text': 'Nope'},
          ],
        },
      });

      final bundler = ManifestBundler();
      await expectLater(
        bundler.bundleProject(path),
        throwsA(isA<BundlerException>().having((e) => e.message, 'message',
            contains('does_not_exist'))),
      );
    });
  });
}
