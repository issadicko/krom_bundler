import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:krom_bundler/src/bundler/asset_packager.dart';
import 'package:krom_bundler/src/bundler/bundler.dart';

void main() {
  group('AssetPackager', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('krom_pkg_test_');
    });

    tearDown(() {
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    });

    /// Write [bytes] to `<tmp>/<relPath>`, creating parent dirs.
    File writeAsset(String relPath, List<int> bytes) {
      final f = File(p.join(tmp.path, relPath));
      f.parent.createSync(recursive: true);
      f.writeAsBytesSync(bytes);
      return f;
    }

    /// Decode the package and return its files keyed by archive name.
    Map<String, ArchiveFile> filesOf(List<int> zipBytes) {
      final archive = ZipDecoder().decodeBytes(zipBytes);
      return {for (final f in archive) f.name: f};
    }

    Map<String, dynamic> baseManifest() => {
          'id': 'com.example.app',
          'name': 'App',
          'version': '1.2.3',
          'entry': 'home',
          'icon': 'assets/icon.png',
          'pages': {
            'home': {'name': 'Home', 'icon': 'bar_chart', 'script': '...'},
          },
        };

    test('package contains app.json + every asset, with a stable layout',
        () async {
      writeAsset('assets/icon.png', utf8.encode('ICON-BYTES'));
      writeAsset('assets/icons/home.png', utf8.encode('HOME-ICON'));

      final manifest = baseManifest()
        ..['tabBar'] = {
          'list': [
            {'pagePath': 'home', 'text': 'Home', 'iconPath': 'assets/icons/home.png'},
          ],
        };

      final result = await AssetPackager.build(
        compiledManifest: manifest,
        projectDir: tmp.path,
      );

      final files = filesOf(result.zipBytes);
      expect(files.keys, contains('app.json'));
      expect(files.keys, contains('assets/icon.png'));
      expect(files.keys, contains('assets/icons/home.png'));
      // Two real image assets discovered.
      expect(result.assets.length, 2);
    });

    test('integrity map sha256 + size match the embedded bytes', () async {
      final iconBytes = utf8.encode('THE-ICON-BYTES');
      writeAsset('assets/icon.png', iconBytes);

      final result = await AssetPackager.build(
        compiledManifest: baseManifest(),
        projectDir: tmp.path,
      );

      // app.json carries the integrity map.
      final appJson = jsonDecode(result.appJson) as Map<String, dynamic>;
      final assetsMap = appJson['assets'] as Map<String, dynamic>;
      final entry = assetsMap['assets/icon.png'] as Map<String, dynamic>;

      final expectedSha = sha256.convert(iconBytes).toString();
      expect(entry['sha256'], expectedSha);
      expect(entry['size'], iconBytes.length);

      // The sha in the map matches the actual bytes stored in the ZIP.
      final files = filesOf(result.zipBytes);
      final stored = files['assets/icon.png']!.content as List<int>;
      expect(sha256.convert(stored).toString(), expectedSha);
      expect(stored, equals(iconBytes));
    });

    test('app.json inside the ZIP equals the returned appJson', () async {
      writeAsset('assets/icon.png', utf8.encode('X'));
      final result = await AssetPackager.build(
        compiledManifest: baseManifest(),
        projectDir: tmp.path,
      );
      final files = filesOf(result.zipBytes);
      final inZip = utf8.decode(files['app.json']!.content as List<int>);
      expect(inZip, result.appJson);
    });

    test('zipSha256Hex is the sha256 of the ZIP bytes', () async {
      writeAsset('assets/icon.png', utf8.encode('X'));
      final result = await AssetPackager.build(
        compiledManifest: baseManifest(),
        projectDir: tmp.path,
      );
      expect(result.zipSha256Hex, sha256.convert(result.zipBytes).toString());
    });

    test('throws when a referenced file asset is missing on disk', () async {
      // icon.png referenced by the manifest but never written.
      expect(
        () => AssetPackager.build(
          compiledManifest: baseManifest(),
          projectDir: tmp.path,
        ),
        throwsA(isA<BundlerException>().having(
            (e) => e.message, 'message', contains('assets/icon.png'))),
      );
    });

    test('Material-style icon names (no extension/slash) are not assets',
        () async {
      // No assets/ dir, and icon is a bare token -> no error, no assets.
      final manifest = baseManifest()..['icon'] = 'account_balance_wallet';
      // page icon 'bar_chart' is also a bare token.
      final result = await AssetPackager.build(
        compiledManifest: manifest,
        projectDir: tmp.path,
      );
      expect(result.assets, isEmpty);
      final appJson = jsonDecode(result.appJson) as Map<String, dynamic>;
      // No assets => no integrity map key at all.
      expect(appJson.containsKey('assets'), isFalse);
    });

    test('sweeps the whole assets/ directory, not just referenced files',
        () async {
      writeAsset('assets/icon.png', utf8.encode('A'));
      writeAsset('assets/extra/font.ttf', utf8.encode('FONT'));
      writeAsset('assets/photo.jpg', utf8.encode('PHOTO'));

      final result = await AssetPackager.build(
        compiledManifest: baseManifest(),
        projectDir: tmp.path,
      );

      final rels = result.assets.map((a) => a.relPath).toList();
      expect(rels, containsAll(<String>[
        'assets/icon.png',
        'assets/extra/font.ttf',
        'assets/photo.jpg',
      ]));
      // Deterministic: sorted.
      final sorted = [...rels]..sort();
      expect(rels, equals(sorted));
    });

    test('tabBar selectedIconPath is collected too', () async {
      writeAsset('assets/icon.png', utf8.encode('A'));
      writeAsset('assets/sel.png', utf8.encode('SEL'));
      final manifest = baseManifest()
        ..['tabBar'] = {
          'list': [
            {
              'pagePath': 'home',
              'text': 'Home',
              'iconPath': 'assets/icon.png',
              'selectedIconPath': 'assets/sel.png',
            },
          ],
        };
      final result = await AssetPackager.build(
        compiledManifest: manifest,
        projectDir: tmp.path,
      );
      expect(result.assets.map((a) => a.relPath), contains('assets/sel.png'));
    });

    test('packageFileName follows <appId>__<version>.zip', () {
      expect(
        AssetPackager.packageFileName('com.example.app', '1.2.3'),
        'com.example.app__1.2.3.zip',
      );
    });

    test('asset-free manifest produces a valid one-file package', () async {
      final manifest = {
        'id': 'a',
        'name': 'A',
        'version': '0.0.1',
        'pages': {
          'home': {'name': 'Home', 'script': '...'},
        },
      };
      final result = await AssetPackager.build(
        compiledManifest: manifest,
        projectDir: tmp.path,
      );
      final files = filesOf(result.zipBytes);
      expect(files.keys, equals({'app.json'}));
      expect(result.assets, isEmpty);
    });
  });
}
