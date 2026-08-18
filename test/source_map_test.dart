import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:krom_bundler/src/bundler/bundler.dart';
import 'package:krom_bundler/src/bundler/manifest_bundler.dart';
import 'package:krom_bundler/src/bundler/source_map.dart';

/// Un projet jetable : `utils/ui.ks` + `components/btn.ks` importés par
/// `pages/home.ks`, la forme qui produit le décalage.
Directory _project({required String home}) {
  final dir = Directory.systemTemp.createTempSync('krom_srcmap_');
  Directory(p.join(dir.path, 'utils')).createSync();
  Directory(p.join(dir.path, 'components')).createSync();
  Directory(p.join(dir.path, 'pages')).createSync();

  File(p.join(dir.path, 'utils', 'ui.ks'))
      .writeAsStringSync('let T = {\n  bg: "#FFF",\n  text: "#000"\n}\n');
  File(p.join(dir.path, 'components', 'btn.ks'))
      .writeAsStringSync('fn Btn(label) {\n  return Button(label, {})\n}\n');
  File(p.join(dir.path, 'pages', 'home.ks')).writeAsStringSync(home);
  File(p.join(dir.path, 'manifest.json')).writeAsStringSync('''
{
  "id": "srcmap",
  "name": "Source map",
  "version": "1.0.0",
  "entry": "home",
  "pages": { "home": { "name": "Accueil", "source": "pages/home.ks" } }
}
''');
  return dir;
}

const _imports = '@use "../utils/ui.ks"\n@use "../components/btn.ks"\n\n';

void main() {
  group('BundleSourceMap', () {
    test('situe une ligne dans le fichier dont elle vient', () {
      final map = BundleSourceMap([
        BundleSegment(path: '/proj/utils/ui.ks', bundleStart: 2, lineCount: 5),
        BundleSegment(
            path: '/proj/pages/home.ks', bundleStart: 9, lineCount: 40),
      ], root: '/proj');

      expect(map.locate(2).toString(), 'utils/ui.ks:1');
      expect(map.locate(6).toString(), 'utils/ui.ks:5');
      expect(map.locate(9).toString(), 'pages/home.ks:1');
      expect(map.locate(48).toString(), 'pages/home.ks:40');
    });

    test('une ligne entre deux fichiers reste sans réponse', () {
      final map = BundleSourceMap([
        BundleSegment(path: '/proj/utils/ui.ks', bundleStart: 2, lineCount: 3),
      ], root: '/proj');

      expect(map.locate(1), isNull); // l'en-tête
      expect(map.locate(5), isNull); // le séparateur
    });

    test('réécrit les trois formats de position du moteur', () {
      final map = BundleSourceMap([
        BundleSegment(
            path: '/proj/pages/home.ks', bundleStart: 10, lineCount: 50),
      ], root: '/proj');

      expect(map.remap('SyntaxError: expected , at line 20:31'),
          'SyntaxError: expected , at pages/home.ks:11:31');
      expect(map.remap('RuntimeError: undefined variable: x at line 20'),
          'RuntimeError: undefined variable: x at pages/home.ks:11');
      expect(map.remap('boom (at line 20:4)'), 'boom (at pages/home.ks:11:4)');
    });

    test('un prélude devant le bundle décale tout ce que le moteur annonce',
        () {
      final map = BundleSourceMap([
        BundleSegment(
            path: '/proj/pages/home.ks', bundleStart: 1, lineCount: 50),
      ], root: '/proj');

      expect(map.remap('err at line 13', preludeLines: 3),
          'err at pages/home.ks:10');
    });

    test('une position hors table garde son numéro brut', () {
      final map = BundleSourceMap([
        BundleSegment(
            path: '/proj/pages/home.ks', bundleStart: 10, lineCount: 5),
      ], root: '/proj');

      expect(map.remap('err at line 900'), 'err at line 900');
    });
  });

  group('Bundler', () {
    test('les @use gardent leur ligne : le fichier ne se décale pas', () async {
      final dir =
          _project(home: '${_imports}fn build() {\n  return Btn("ok")\n}\n');
      addTearDown(() => dir.deleteSync(recursive: true));

      final bundler = Bundler(projectRoot: dir.path);
      final bundle = await bundler.bundle(p.join(dir.path, 'pages', 'home.ks'));
      final lines = bundle.split('\n');

      // `fn build()` est à la ligne 4 de home.ks (2 @use + 1 vide).
      final segment = bundler.sourceMap!.segments
          .firstWhere((s) => s.path.endsWith('home.ks'));
      expect(lines[segment.bundleStart + 2], 'fn build() {');
      expect(bundler.sourceMap!.locate(segment.bundleStart + 3).toString(),
          'pages/home.ks:4');
    });

    test('chaque ligne du bundle retombe sur sa ligne de fichier', () async {
      final dir =
          _project(home: '${_imports}fn build() {\n  return Btn(T.bg)\n}\n');
      addTearDown(() => dir.deleteSync(recursive: true));

      final bundler = Bundler(projectRoot: dir.path);
      final bundle = await bundler.bundle(p.join(dir.path, 'pages', 'home.ks'));
      final bundleLines = bundle.split('\n');

      for (final segment in bundler.sourceMap!.segments) {
        final source = File(segment.path).readAsLinesSync();
        for (var i = 0; i < source.length; i++) {
          // Les `@use` sont blanchis dans le bundle : la ligne survit, pas
          // son contenu — c'est précisément ce qui préserve la numérotation.
          if (source[i].trimLeft().startsWith('@use')) {
            expect(bundleLines[segment.bundleStart + i - 1].trim(), '');
            continue;
          }
          final where = bundler.sourceMap!.locate(segment.bundleStart + i)!;
          expect(bundleLines[segment.bundleStart + i - 1], source[i],
              reason: 'ligne ${where.path}:${where.line}');
        }
      }
    });
  });

  group('krom build / krom dev', () {
    test('une virgule manquante est signalée à la ligne du fichier', () async {
      final dir = _project(
          home: '${_imports}fn build() {\n'
              '  return Box({\n'
              '    padding: 0\n'
              '    color: "#FFF"\n'
              '  })\n'
              '}\n');
      addTearDown(() => dir.deleteSync(recursive: true));

      // `padding: 0` est à la ligne 6 de pages/home.ks.
      await expectLater(
        ManifestBundler(enableOptimizer: true)
            .bundleProjectToMap(p.join(dir.path, 'manifest.json')),
        throwsA(isA<BundlerException>().having(
            (e) => e.message, 'message', contains('at pages/home.ks:6:'))),
      );
    });

    // Depuis krom_script 1.0.3, une erreur d'exécution porte sa position : la
    // validation du premier niveau est donc située elle aussi, et pas
    // seulement la syntaxe.
    test('une erreur de validation est située dans le fichier', () async {
      final dir = _project(
          home: '${_imports}let couleur = paletteInexistante\n\n'
              'fn build() {\n  return Btn("ok")\n}\n');
      addTearDown(() => dir.deleteSync(recursive: true));

      await expectLater(
        ManifestBundler().bundleProjectToMap(p.join(dir.path, 'manifest.json')),
        throwsA(isA<BundlerException>().having(
            (e) => e.message,
            'message',
            contains(
                'undefined variable: paletteInexistante at pages/home.ks:4'))),
      );
    });

    // `krom dev` n'optimise pas : la faute de syntaxe ressort alors de la
    // validation, et non de l'étape d'optimisation. Elle doit être située de
    // la même façon — c'est le chemin que le développeur emprunte le plus.
    test('sans optimisation (krom dev), la position est la même', () async {
      final dir = _project(
          home: '${_imports}fn build() {\n'
              '  return Box({\n'
              '    padding: 0\n'
              '    color: "#FFF"\n'
              '  })\n'
              '}\n');
      addTearDown(() => dir.deleteSync(recursive: true));

      await expectLater(
        ManifestBundler().bundleProjectToMap(p.join(dir.path, 'manifest.json')),
        throwsA(isA<BundlerException>().having(
            (e) => e.message, 'message', contains('at pages/home.ks:6:'))),
      );
    });
  });

  group('table embarquée dans le manifeste', () {
    test('krom dev écrit la table dans chaque page', () async {
      final dir =
          _project(home: '${_imports}fn build() {\n  return Btn("ok")\n}\n');
      addTearDown(() => dir.deleteSync(recursive: true));

      final manifest = await ManifestBundler(emitSourceMap: true)
          .bundleProjectToMap(p.join(dir.path, 'manifest.json'));
      final page = (manifest['pages'] as Map)['home'] as Map;
      final map = (page['sourceMap'] as List).cast<Map>();

      expect(map.map((s) => s['f']),
          containsAll(['utils/ui.ks', 'components/btn.ks', 'pages/home.ks']));

      // La table doit retomber sur le script effectivement publié.
      final lines = (page['script'] as String).split('\n');
      final home = map.firstWhere((s) => s['f'] == 'pages/home.ks');
      final source =
          File(p.join(dir.path, 'pages', 'home.ks')).readAsLinesSync();
      expect(
          lines[(home['d'] as int) + 2], source[3]); // 1re ligne après les @use
    });

    test("un bundle publié n'embarque pas de table", () async {
      final dir =
          _project(home: '${_imports}fn build() {\n  return Btn("ok")\n}\n');
      addTearDown(() => dir.deleteSync(recursive: true));

      // Le texte est réécrit par l'optimiseur : une table y serait fausse.
      final manifest = await ManifestBundler(enableOptimizer: true)
          .bundleProjectToMap(p.join(dir.path, 'manifest.json'));
      final page = (manifest['pages'] as Map)['home'] as Map;

      expect(page.containsKey('sourceMap'), isFalse);
    });
  });
}
