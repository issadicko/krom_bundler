import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:krom_bundler/src/bundler/asset_packager.dart';

/// Le canal de dev ne transportait que le script : une image du projet
/// s'affichait en carré gris sur l'appareil, alors qu'elle marchait dans le
/// navigateur (où le serveur de dev la sert). Ces deux briques — la collecte et
/// la carte d'intégrité — sont ce qui permet de n'envoyer que ce qui a changé.

Directory _project() {
  final dir = Directory.systemTemp.createTempSync('krom_devassets_');
  addTearDown(() => dir.deleteSync(recursive: true));

  Directory(p.join(dir.path, 'assets', 'images')).createSync(recursive: true);
  Directory(p.join(dir.path, 'pages')).createSync();

  File(p.join(dir.path, 'assets', 'images', 'logo.png'))
      .writeAsBytesSync([1, 2, 3]);
  File(p.join(dir.path, 'assets', 'data.json')).writeAsStringSync('{}');
  File(p.join(dir.path, 'pages', 'home.ks'))
      .writeAsStringSync('fn build() { return Image("assets/images/logo.png") }\n');
  return dir;
}

const _manifest = {
  'id': 'demo',
  'version': '1.0.0',
  'pages': {
    'home': {'script': 'fn build() { return null }'}
  },
};

void main() {
  group('collecte des assets', () {
    test('ramasse tout le dossier assets/', () async {
      final dir = _project();
      final assets = await AssetPackager.collect(
        compiledManifest: _manifest,
        projectDir: dir.path,
      );

      expect(assets.map((a) => a.relPath).toList(),
          containsAll(['assets/data.json', 'assets/images/logo.png']));
    });

    test('chaque asset porte ses octets, sa taille et son empreinte', () async {
      final dir = _project();
      final assets = await AssetPackager.collect(
        compiledManifest: _manifest,
        projectDir: dir.path,
      );
      final logo = assets.firstWhere((a) => a.relPath.endsWith('logo.png'));

      expect(logo.bytes, [1, 2, 3]);
      expect(logo.size, 3);
      expect(logo.sha256Hex.length, 64);
    });

    test('la carte d\'intégrité est ce que le canal compare', () async {
      final dir = _project();
      final assets = await AssetPackager.collect(
        compiledManifest: _manifest,
        projectDir: dir.path,
      );
      final map = AssetPackager.integrityMap(assets);

      expect(map.keys, containsAll(['assets/images/logo.png']));
      final entry = map['assets/images/logo.png'] as Map;
      expect(entry['size'], 3);
      expect(entry['sha256'],
          assets.firstWhere((a) => a.relPath.endsWith('logo.png')).sha256Hex);
    });

    test('une empreinte suit le contenu du fichier', () async {
      final dir = _project();
      final before = await AssetPackager.collect(
        compiledManifest: _manifest,
        projectDir: dir.path,
      );

      File(p.join(dir.path, 'assets', 'images', 'logo.png'))
          .writeAsBytesSync([9, 9, 9, 9]);

      final after = await AssetPackager.collect(
        compiledManifest: _manifest,
        projectDir: dir.path,
      );

      String sha(List<PackagedAsset> list) =>
          list.firstWhere((a) => a.relPath.endsWith('logo.png')).sha256Hex;
      expect(sha(after), isNot(sha(before)));
    });

    test('un projet sans assets ne collecte rien', () async {
      final dir = Directory.systemTemp.createTempSync('krom_noassets_');
      addTearDown(() => dir.deleteSync(recursive: true));

      final assets = await AssetPackager.collect(
        compiledManifest: _manifest,
        projectDir: dir.path,
      );
      expect(assets, isEmpty);
      expect(AssetPackager.integrityMap(assets), isEmpty);
    });
  });
}
