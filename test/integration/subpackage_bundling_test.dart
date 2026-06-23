import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:krom_bundler/src/bundler/manifest_bundler.dart';
import 'package:krom_bundler/src/bundler/bundler.dart';
import 'package:path/path.dart' as p;

/// Integration tests for the actual subpackage (分包) split performed by
/// [ManifestBundler.bundleProject]: pages listed in a subpackage must land in
/// that subpackage's compiled bundle and must NOT be duplicated in the main
/// package, while every other page stays in the main package.
void main() {
  group('ManifestBundler subpackage bundling', () {
    final tempDir = Directory('test_temp_subpackage');

    setUp(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
      await tempDir.create();
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    Future<void> writePage(String name, String label) async {
      await File(p.join(tempDir.path, '$name.ks')).writeAsString('''
fn build() {
  return Text("$label")
}
''');
    }

    Future<String> writeManifest(Map<String, dynamic> m) async {
      final f = File(p.join(tempDir.path, 'manifest.json'));
      await f.writeAsString(jsonEncode(m));
      return f.path;
    }

    /// A project with a main page (home) plus two pages that belong to a
    /// "packageStats" subpackage.
    Future<String> writeStatsProject() async {
      await writePage('home', 'home');
      await writePage('detail', 'detail');
      await writePage('export', 'export');
      return writeManifest({
        'id': 'app',
        'name': 'App',
        'version': '1.0.0',
        'entry': 'home',
        'pages': {
          'home': {'name': 'Home', 'source': 'home.ks'},
          'detail': {'name': 'Detail', 'source': 'detail.ks'},
          'export': {'name': 'Export', 'source': 'export.ks'},
        },
        'subpackages': [
          {
            'root': 'packageStats',
            'pages': ['detail', 'export'],
          },
        ],
      });
    }

    test('splits pages between main package and subpackage', () async {
      final path = await writeStatsProject();
      final out = jsonDecode(await ManifestBundler().bundleProject(path))
          as Map<String, dynamic>;

      // Main package keeps only the non-subpackage page.
      final mainPages = out['pages'] as Map<String, dynamic>;
      expect(mainPages.keys, equals({'home'}));

      // Subpackage carries its two pages with compiled scripts.
      final subpackages = out['subpackages'] as List<dynamic>;
      expect(subpackages, hasLength(1));
      final pkg = subpackages.first as Map<String, dynamic>;
      expect(pkg['root'], 'packageStats');
      final pkgPages = pkg['pages'] as Map<String, dynamic>;
      expect(pkgPages.keys, equals({'detail', 'export'}));
      expect((pkgPages['detail'] as Map)['script'], isA<String>());
      expect((pkgPages['detail'] as Map)['script'], contains('detail'));
    });

    test('does not duplicate subpackage pages in the main package', () async {
      final path = await writeStatsProject();
      final out = jsonDecode(await ManifestBundler().bundleProject(path))
          as Map<String, dynamic>;

      final mainPages = (out['pages'] as Map<String, dynamic>).keys.toSet();
      final pkg = (out['subpackages'] as List).first as Map<String, dynamic>;
      final pkgPages = (pkg['pages'] as Map<String, dynamic>).keys.toSet();

      // No page appears in both the main package and a subpackage.
      expect(mainPages.intersection(pkgPages), isEmpty);
      expect(mainPages, equals({'home'}));
      expect(pkgPages, equals({'detail', 'export'}));
    });

    test('emits no subpackages key when none are declared', () async {
      await writePage('home', 'home');
      final path = await writeManifest({
        'id': 'app',
        'name': 'App',
        'version': '1.0.0',
        'entry': 'home',
        'pages': {
          'home': {'name': 'Home', 'source': 'home.ks'},
        },
      });
      final out = jsonDecode(await ManifestBundler().bundleProject(path))
          as Map<String, dynamic>;
      expect(out.containsKey('subpackages'), isFalse);
      expect((out['pages'] as Map).keys, equals({'home'}));
    });

    test('preserves extra subpackage metadata (e.g. independent)', () async {
      await writePage('home', 'home');
      await writePage('detail', 'detail');
      final path = await writeManifest({
        'id': 'app',
        'name': 'App',
        'version': '1.0.0',
        'entry': 'home',
        'pages': {
          'home': {'name': 'Home', 'source': 'home.ks'},
          'detail': {'name': 'Detail', 'source': 'detail.ks'},
        },
        'subpackages': [
          {
            'root': 'pkg',
            'independent': true,
            'pages': ['detail'],
          },
        ],
      });
      final out = jsonDecode(await ManifestBundler().bundleProject(path))
          as Map<String, dynamic>;
      final pkg = (out['subpackages'] as List).first as Map<String, dynamic>;
      expect(pkg['independent'], isTrue);
      expect((pkg['pages'] as Map).keys, equals({'detail'}));
    });

    test('rejects a subpackage page missing from pages', () async {
      await writePage('home', 'home');
      final path = await writeManifest({
        'id': 'app',
        'name': 'App',
        'version': '1.0.0',
        'entry': 'home',
        'pages': {
          'home': {'name': 'Home', 'source': 'home.ks'},
        },
        'subpackages': [
          {
            'root': 'pkg',
            'pages': ['ghost'],
          },
        ],
      });
      await expectLater(
        ManifestBundler().bundleProject(path),
        throwsA(isA<BundlerException>()
            .having((e) => e.message, 'message', contains('ghost'))),
      );
    });

    test('rejects the entry page being placed in a subpackage', () async {
      await writePage('home', 'home');
      await writePage('detail', 'detail');
      final path = await writeManifest({
        'id': 'app',
        'name': 'App',
        'version': '1.0.0',
        'entry': 'home',
        'pages': {
          'home': {'name': 'Home', 'source': 'home.ks'},
          'detail': {'name': 'Detail', 'source': 'detail.ks'},
        },
        'subpackages': [
          {
            'root': 'pkg',
            'pages': ['home', 'detail'],
          },
        ],
      });
      await expectLater(
        ManifestBundler().bundleProject(path),
        throwsA(isA<BundlerException>()
            .having((e) => e.message, 'message', contains('Entry page'))),
      );
    });

    test('supports multiple subpackages', () async {
      await writePage('home', 'home');
      await writePage('a', 'a');
      await writePage('b', 'b');
      final path = await writeManifest({
        'id': 'app',
        'name': 'App',
        'version': '1.0.0',
        'entry': 'home',
        'pages': {
          'home': {'name': 'Home', 'source': 'home.ks'},
          'a': {'name': 'A', 'source': 'a.ks'},
          'b': {'name': 'B', 'source': 'b.ks'},
        },
        'subpackages': [
          {
            'root': 'pkgA',
            'pages': ['a'],
          },
          {
            'root': 'pkgB',
            'pages': ['b'],
          },
        ],
      });
      final out = jsonDecode(await ManifestBundler().bundleProject(path))
          as Map<String, dynamic>;
      expect((out['pages'] as Map).keys, equals({'home'}));
      final pkgs = (out['subpackages'] as List).cast<Map<String, dynamic>>();
      final byRoot = {for (final p in pkgs) p['root'] as String: p};
      expect((byRoot['pkgA']!['pages'] as Map).keys, equals({'a'}));
      expect((byRoot['pkgB']!['pages'] as Map).keys, equals({'b'}));
    });
  });
}
