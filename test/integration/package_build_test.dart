import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:krom_bundler/src/bundler/asset_packager.dart';
import 'package:krom_bundler/src/bundler/manifest_bundler.dart';

/// End-to-end: a real project (manifest + .ks pages + a binary asset) goes
/// through [ManifestBundler] then [AssetPackager], yielding the signed-ready
/// `<appId>__<version>.zip` whose app.json carries inlined scripts *and* a
/// matching per-asset integrity map.
void main() {
  group('build → package integration', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('krom_pkg_int_');
      // A page with KromScript so the compiled app.json has an inlined script.
      File(p.join(tmp.path, 'home.ks')).writeAsStringSync('''
fn build() {
  return Text("hi")
}
''');
      // A real binary asset (PNG header bytes are enough for hashing).
      final iconDir = Directory(p.join(tmp.path, 'assets'))
        ..createSync(recursive: true);
      File(p.join(iconDir.path, 'icon.png'))
          .writeAsBytesSync(<int>[0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);
      File(p.join(tmp.path, 'manifest.json')).writeAsStringSync(jsonEncode({
        'id': 'com.example.app',
        'name': 'App',
        'version': '2.0.0',
        'icon': 'assets/icon.png',
        'entry': 'home',
        'pages': {
          'home': {'name': 'Home', 'source': 'home.ks'},
        },
      }));
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    test('compiles scripts and bundles assets with matching sha256', () async {
      final manifestPath = p.join(tmp.path, 'manifest.json');
      final bundler = ManifestBundler(enableOptimizer: false, minify: false);
      final compiled = await bundler.bundleProjectToMap(manifestPath);

      // The compiled manifest has an inlined script for the page.
      final pages = compiled['pages'] as Map<String, dynamic>;
      expect((pages['home'] as Map)['script'], contains('build'));

      final result = await AssetPackager.build(
        compiledManifest: compiled,
        projectDir: tmp.path,
      );

      // ZIP carries app.json + the asset.
      final archive = ZipDecoder().decodeBytes(result.zipBytes);
      final names = archive.map((f) => f.name).toSet();
      expect(names, containsAll(<String>['app.json', 'assets/icon.png']));

      // The on-disk asset's sha256 == integrity-map sha256 == ZIP-entry sha256.
      final diskBytes =
          File(p.join(tmp.path, 'assets', 'icon.png')).readAsBytesSync();
      final diskSha = sha256.convert(diskBytes).toString();

      final appJson = jsonDecode(result.appJson) as Map<String, dynamic>;
      final mapEntry =
          (appJson['assets'] as Map)['assets/icon.png'] as Map<String, dynamic>;
      expect(mapEntry['sha256'], diskSha);
      expect(mapEntry['size'], diskBytes.length);

      final zipEntry = archive.firstWhere((f) => f.name == 'assets/icon.png');
      expect(sha256.convert(zipEntry.content as List<int>).toString(), diskSha);

      // Package file name contract.
      expect(
        AssetPackager.packageFileName(
            compiled['id'] as String, compiled['version'] as String),
        'com.example.app__2.0.0.zip',
      );
    });

    test('a manifest-referenced but missing asset fails the build', () async {
      // Point the icon at a file that does not exist.
      File(p.join(tmp.path, 'manifest.json')).writeAsStringSync(jsonEncode({
        'id': 'com.example.app',
        'name': 'App',
        'version': '2.0.0',
        'icon': 'assets/missing.png',
        'entry': 'home',
        'pages': {
          'home': {'name': 'Home', 'source': 'home.ks'},
        },
      }));
      Directory(p.join(tmp.path, 'assets')).deleteSync(recursive: true);

      final bundler = ManifestBundler();
      final compiled = await bundler.bundleProjectToMap(
        p.join(tmp.path, 'manifest.json'),
      );
      expect(
        () => AssetPackager.build(
          compiledManifest: compiled,
          projectDir: tmp.path,
        ),
        throwsA(predicate(
            (e) => e.toString().contains('assets/missing.png'))),
      );
    });
  });
}
