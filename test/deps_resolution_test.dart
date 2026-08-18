import 'dart:io';

import 'package:krom_script/krom_script.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:krom_bundler/src/bundler/bundler.dart';
import 'package:krom_bundler/src/bundler/manifest_bundler.dart';

/// Un projet jetable. [files] est un chemin relatif -> contenu.
Directory _project(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('krom_depres_');
  files.forEach((relative, content) {
    final file = File(p.join(dir.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  });
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

Future<String> _bundle(Directory dir, String entry,
    {Map<String, String> depRoots = const {}}) {
  final bundler = Bundler(projectRoot: dir.path, depRoots: depRoots);
  return bundler.bundle(p.join(dir.path, entry));
}

/// Charge le bundle et appelle `probe()`, ce que ferait le runtime.
Future<Object?> _run(String bundle) async {
  final engine = KSEngine();
  final loaded = await engine.load(bundle, enableOptimizer: false);
  expect(loaded.success, isTrue, reason: loaded.errors.join('\n'));
  final result = await engine.invoke('probe');
  expect(result.success, isTrue, reason: result.errors.join('\n'));
  return result.value;
}

Map<String, String> _money(Directory dir) =>
    {'money': p.join(dir.path, '.krom', 'deps', 'money')};

const _gitUrl = 'https://git.example/ks-money.git';

/// Les fichiers d'un projet à manifeste dont la dépendance `money` est
/// installée et conforme au lock — sauf ce que [without] retire.
Map<String, String> _manifestProject({Set<String> without = const {}}) {
  final files = {
    'manifest.json': '''
{
  "id": "t", "name": "T", "version": "1.0.0", "entry": "home",
  "pages": {"home": {"name": "Home", "source": "pages/home.ks"}},
  "dependencies": {"money": {"git": "$_gitUrl", "ref": "v1.0.0"}}
}
''',
    'krom.lock': '''
{
  "version": 1,
  "deps": {
    "money": {"git": "$_gitUrl", "ref": "v1.0.0", "commit": "abc123"}
  }
}
''',
    '.krom/deps/money/.dep.json': '''
{"git": "$_gitUrl", "ref": "v1.0.0", "commit": "abc123"}
''',
    '.krom/deps/money/format.ks': 'fn label(n) { return "" + n + " F" }\n',
    'pages/home.ks': '@use "money/format" as fmt\n'
        'fn build() { return fmt.label(5) }\n',
  };
  files.removeWhere((key, _) => without.contains(key));
  return files;
}

void main() {
  group('résolution des imports de dépendances', () {
    test('premier segment déclaré -> fichier de la dépendance', () async {
      final dir = _project({
        '.krom/deps/money/format.ks': 'fn label(n) { return "" + n + " F" }\n',
        'pages/home.ks': '@use "money/format" as fmt\n'
            'fn probe() { return fmt.label(5) }\n',
      });
      final bundle = await _bundle(dir, 'pages/home.ks', depRoots: _money(dir));
      expect(await _run(bundle), '5 F');
    });

    test('@use "money" nu -> main.ks de la dépendance', () async {
      final dir = _project({
        '.krom/deps/money/main.ks': 'fn devise() { return "XOF" }\n',
        'pages/home.ks': '@use "money" as money\n'
            'fn probe() { return money.devise() }\n',
      });
      final bundle = await _bundle(dir, 'pages/home.ks', depRoots: _money(dir));
      expect(await _run(bundle), 'XOF');
    });

    test('un chemin nu hors dépendances reste relatif', () async {
      final dir = _project({
        'pages/utils/helpers.ks': 'fn aide() { return "ok" }\n',
        'pages/home.ks': '@use "utils/helpers"\n'
            'fn probe() { return aide() }\n',
      });
      final bundle = await _bundle(dir, 'pages/home.ks', depRoots: _money(dir));
      expect(await _run(bundle), 'ok');
    });

    test('"money.ks" explicite ne désigne pas la dépendance money', () async {
      final dir = _project({
        'pages/money.ks': 'fn local() { return "local" }\n',
        'pages/home.ks': '@use "money.ks"\n'
            'fn probe() { return local() }\n',
      });
      final bundle = await _bundle(dir, 'pages/home.ks', depRoots: _money(dir));
      expect(await _run(bundle), 'local');
    });

    test('un fichier local homonyme -> erreur franche, pas d\'ombrage',
        () async {
      final dir = _project({
        '.krom/deps/money/format.ks': 'fn label(n) { return "" }\n',
        'pages/money/format.ks': 'fn label(n) { return "" }\n',
        'pages/home.ks': '@use "money/format" as fmt\n'
            'fn probe() { return fmt.label(5) }\n',
      });
      await expectLater(
          _bundle(dir, 'pages/home.ks', depRoots: _money(dir)),
          throwsA(isA<BundlerException>()
              .having((e) => e.message, 'message', contains('ambiguous'))));
    });

    test('./ explicite garde le fichier local malgré la dépendance', () async {
      final dir = _project({
        '.krom/deps/money/format.ks': 'fn label(n) { return "dep" }\n',
        'pages/money/format.ks': 'fn label(n) { return "local" }\n',
        'pages/home.ks': '@use "./money/format" as fmt\n'
            'fn probe() { return fmt.label(5) }\n',
      });
      final bundle = await _bundle(dir, 'pages/home.ks', depRoots: _money(dir));
      expect(await _run(bundle), 'local');
    });

    test('un import ne peut pas sortir de la dépendance', () async {
      final dir = _project({
        '.krom/deps/money/format.ks': 'fn label(n) { return "" }\n',
        'pages/home.ks': '@use "money/../secret" as s\n'
            'fn probe() { return null }\n',
      });
      await expectLater(
          _bundle(dir, 'pages/home.ks', depRoots: _money(dir)),
          throwsA(isA<BundlerException>().having(
              (e) => e.message, 'message', contains('escapes dependency'))));
    });

    test('les fichiers d\'une dépendance s\'importent entre eux en relatif',
        () async {
      final dir = _project({
        '.krom/deps/money/devises.ks': 'let SYMBOLE = "F"\n',
        '.krom/deps/money/format.ks': '@use "./devises.ks"\n'
            'fn label(n) { return "" + n + " " + SYMBOLE }\n',
        'pages/home.ks': '@use "money/format" as fmt\n'
            'fn probe() { return fmt.label(3) }\n',
      });
      final bundle = await _bundle(dir, 'pages/home.ks', depRoots: _money(dir));
      expect(await _run(bundle), '3 F');
    });
  });

  group('collisions de noms entre paquets', () {
    Matcher refuse(String nom, String fragment) =>
        throwsA(isA<BundlerException>()
            .having((e) => e.message, 'message', contains('"$nom" is claimed'))
            .having((e) => e.message, 'message', contains(fragment)));

    test('le projet ne peut pas écraser un nom interne de la dépendance',
        () async {
      // Le cas silencieux : format.ks tire couleurs.ks à plat, ses noms
      // atterrissent au premier niveau, et un homonyme du projet gagnait.
      final dir = _project({
        '.krom/deps/money/couleurs.ks': 'let VERT = "vert-de-la-lib"\n',
        '.krom/deps/money/format.ks': '@use "./couleurs.ks"\n'
            'fn couleur() { return VERT }\n',
        'pages/home.ks': '@use "money/format" as fmt\n'
            'let VERT = "rouge-du-projet"\n'
            'fn probe() { return fmt.couleur() }\n',
      });
      await expectLater(_bundle(dir, 'pages/home.ks', depRoots: _money(dir)),
          refuse('VERT', 'couleurs.ks'));
    });

    test('ni reprendre le nom sous lequel la dépendance aliase son module',
        () async {
      final dir = _project({
        '.krom/deps/money/couleurs.ks': 'let VERT = "vert-de-la-lib"\n',
        '.krom/deps/money/format.ks': '@use "./couleurs.ks" as c\n'
            'fn couleur() { return c.VERT }\n',
        'pages/home.ks': '@use "money/format" as fmt\n'
            'let c = { VERT: "rouge-du-projet" }\n'
            'fn probe() { return fmt.couleur() }\n',
      });
      await expectLater(_bundle(dir, 'pages/home.ks', depRoots: _money(dir)),
          refuse('c', 'format.ks'));
    });

    test('deux dépendances ne peuvent pas poser le même nom', () async {
      final dir = _project({
        '.krom/deps/money/util.ks': 'let TAILLE = 1\n',
        '.krom/deps/money/main.ks':
            '@use "./util.ks"\nfn a() { return TAILLE }\n',
        '.krom/deps/ui/util.ks': 'let TAILLE = 2\n',
        '.krom/deps/ui/main.ks': '@use "./util.ks"\nfn b() { return TAILLE }\n',
        'pages/home.ks': '@use "money" as m\n@use "ui" as u\n'
            'fn probe() { return m.a() + u.b() }\n',
      });
      await expectLater(
          _bundle(dir, 'pages/home.ks', depRoots: {
            ..._money(dir),
            'ui': p.join(dir.path, '.krom', 'deps', 'ui'),
          }),
          refuse('TAILLE', 'util.ks'));
    });

    test('le même alias pour le même module des deux côtés reste légal',
        () async {
      final dir = _project({
        '.krom/deps/money/couleurs.ks': 'let VERT = "#0F8A3C"\n',
        '.krom/deps/money/format.ks': '@use "./couleurs.ks" as couleurs\n'
            'fn couleur() { return couleurs.VERT }\n',
        'pages/home.ks': '@use "money/format" as fmt\n'
            '@use "money/couleurs" as couleurs\n'
            'fn probe() { return fmt.couleur() + "/" + couleurs.VERT }\n',
      });
      final bundle = await _bundle(dir, 'pages/home.ks', depRoots: _money(dir));
      expect(await _run(bundle), '#0F8A3C/#0F8A3C');
    });

    test('entre fichiers du projet, la règle historique tient', () async {
      // Deux fichiers à plat du MÊME paquet : le dernier gagne, comme avant.
      // Leur auteur voit les deux — rien à arbitrer à sa place.
      final dir = _project({
        '.krom/deps/money/main.ks': 'fn devise() { return "XOF" }\n',
        'pages/a.ks': 'let T = "a"\n',
        'pages/b.ks': 'let T = "b"\n',
        'pages/home.ks': '@use "money" as money\n'
            '@use "./a.ks"\n@use "./b.ks"\n'
            'fn probe() { return T + money.devise() }\n',
      });
      final bundle = await _bundle(dir, 'pages/home.ks', depRoots: _money(dir));
      expect(await _run(bundle), 'bXOF');
    });
  });

  group('ManifestBundler et l\'état des dépendances', () {
    Future<Map<String, dynamic>> bundleProject(Directory dir) =>
        ManifestBundler().bundleProjectToMap(p.join(dir.path, 'manifest.json'));

    Matcher throwsNotReady(String fragment) => throwsA(isA<BundlerException>()
        .having((e) => e.message, 'message', contains('Dependencies are not'))
        .having((e) => e.message, 'message', contains(fragment)));

    test('dépendance installée au commit du lock : le projet bundle', () async {
      final dir = _project(_manifestProject());
      final result = await bundleProject(dir);
      final script =
          ((result['pages'] as Map)['home'] as Map)['script'] as String;
      expect(script, contains('label'));
    });

    test('sans krom.lock : arrêt net avec la commande à lancer', () async {
      final dir = _project(_manifestProject(without: {'krom.lock'}));
      await expectLater(bundleProject(dir), throwsNotReady('is not locked'));
    });

    test('verrouillée mais pas installée', () async {
      final dir =
          _project(_manifestProject(without: {'.krom/deps/money/.dep.json'}));
      await expectLater(bundleProject(dir), throwsNotReady('is not installed'));
    });

    test('installée à un autre commit que le lock', () async {
      final dir = _project(_manifestProject());
      File(p.join(dir.path, '.krom/deps/money/.dep.json')).writeAsStringSync(
          '{"git": "$_gitUrl", "ref": "v1.0.0", "commit": "autre"}');
      await expectLater(bundleProject(dir), throwsNotReady('different commit'));
    });

    test('le manifeste a changé de ref depuis la résolution', () async {
      final dir = _project(_manifestProject());
      final manifest = File(p.join(dir.path, 'manifest.json'));
      manifest.writeAsStringSync(manifest
          .readAsStringSync()
          .replaceFirst('"ref": "v1.0.0"}}', '"ref": "v2.0.0"}}'));
      await expectLater(bundleProject(dir), throwsNotReady('is not locked'));
    });

    test('sans dependencies : rien ne change', () async {
      final dir = _project({
        'manifest.json': '''
{
  "id": "t", "name": "T", "version": "1.0.0", "entry": "home",
  "pages": {"home": {"name": "Home", "source": "pages/home.ks"}}
}
''',
        'pages/utils/helpers.ks': 'fn aide() { return "ok" }\n',
        'pages/home.ks': '@use "utils/helpers"\n'
            'fn build() { return aide() }\n',
      });
      final result = await bundleProject(dir);
      final script =
          ((result['pages'] as Map)['home'] as Map)['script'] as String;
      expect(script, contains('aide'));
    });
  });
}
