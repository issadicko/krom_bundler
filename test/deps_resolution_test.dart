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
