import 'dart:io';

import 'package:krom_script/krom_script.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:krom_bundler/src/bundler/bundler.dart';
import 'package:krom_bundler/src/bundler/module_scope.dart';

/// Un projet jetable. [files] est un chemin relatif -> contenu.
Directory _project(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('krom_scope_');
  files.forEach((relative, content) {
    final file = File(p.join(dir.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  });
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

Future<String> _bundle(Directory dir, String entry,
    {Set<String> reserved = const {}}) {
  final bundler = Bundler(projectRoot: dir.path, reservedNames: reserved);
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

void main() {
  group('@use ... as', () {
    test('deux modules peuvent déclarer le même nom', () async {
      final dir = _project({
        'utils/ui.ks': 'let T = { primary: "#123456" }\n'
            'fn tint() { return T.primary }\n',
        'features/qr.ks': 'let T = { primary: "#000000" }\n'
            'fn render() { return T.primary }\n',
        'pages/home.ks': '@use "../utils/ui.ks" as palette\n'
            '@use "../features/qr.ks" as qr\n'
            'fn probe() { return palette.tint() + "/" + qr.render() }\n',
      });

      expect(await _run(await _bundle(dir, 'pages/home.ks')),
          '#123456/#000000');
    });

    test('la forme à plat, elle, laisse le dernier fichier gagner', () async {
      // Le comportement historique, conservé tel quel — et la raison d'être
      // de `as`.
      final dir = _project({
        'utils/ui.ks': 'let T = { primary: "#123456" }\n'
            'fn tint() { return T.primary }\n',
        'features/qr.ks': 'let T = { primary: "#000000" }\n',
        'pages/home.ks': '@use "../utils/ui.ks"\n'
            '@use "../features/qr.ks"\n'
            'fn probe() { return tint() }\n',
      });

      expect(await _run(await _bundle(dir, 'pages/home.ks')), '#000000');
    });

    test('un module importé deux fois n\'est émis qu\'une fois', () async {
      final dir = _project({
        'utils/ui.ks': 'let T = { primary: "#123456" }\n',
        'features/a.ks': '@use "../utils/ui.ks" as palette\n'
            'fn a() { return palette.T.primary }\n',
        'features/b.ks': '@use "../utils/ui.ks" as skin\n'
            'fn b() { return skin.T.primary }\n',
        'pages/home.ks': '@use "../features/a.ks" as fa\n'
            '@use "../features/b.ks" as fb\n'
            'fn probe() { return fa.a() + fb.b() }\n',
      });

      final bundle = await _bundle(dir, 'pages/home.ks');
      expect('let __m_utils_ui = fn() {'.allMatches(bundle).length, 1);
      // Un alias par importeur, tous deux pointant sur la même valeur.
      expect(bundle, contains('let palette = __m_utils_ui'));
      expect(bundle, contains('let skin = __m_utils_ui'));
      expect(await _run(bundle), '#123456#123456');
    });

    test('deux fichiers de même nom de base restent distincts', () async {
      final dir = _project({
        'a/ui.ks': 'fn tint() { return "a" }\n',
        'b/ui.ks': 'fn tint() { return "b" }\n',
        'pages/home.ks': '@use "../a/ui.ks" as ua\n'
            '@use "../b/ui.ks" as ub\n'
            'fn probe() { return ua.tint() + ub.tint() }\n',
      });

      expect(await _run(await _bundle(dir, 'pages/home.ks')), 'ab');
    });

    test('un module scopé voit les globaux de l\'hôte', () async {
      final dir = _project({
        'utils/ui.ks': 'let T = { primary: theme.primary }\n',
        'pages/home.ks': '@use "../utils/ui.ks" as palette\n'
            'fn probe() { return palette.T.primary }\n',
      });

      final engine = KSEngine();
      engine.setVariable('theme', {'primary': '#6750A4'});
      final bundle = await _bundle(dir, 'pages/home.ks');
      final loaded = await engine.load(bundle, enableOptimizer: false);
      expect(loaded.success, isTrue, reason: loaded.errors.join('\n'));
      expect((await engine.invoke('probe')).value, '#6750A4');
    });

    test('un callback par nom pointé atteint la fonction du module', () async {
      // C'est la forme que produit `builder: "homeView.homeTab"`.
      final dir = _project({
        'utils/views.ks': 'fn homeTab() { return "tab" }\n',
        'pages/home.ks': '@use "../utils/views.ks" as views\n'
            'fn probe() { return 1 }\n',
      });

      final engine = KSEngine();
      final loaded = await engine.load(await _bundle(dir, 'pages/home.ks'),
          enableOptimizer: false);
      expect(loaded.success, isTrue, reason: loaded.errors.join('\n'));
      expect(engine.invokeSync('views.homeTab'), 'tab');
    });
  });

  group('erreurs de portée', () {
    Future<void> expectRefus(Directory dir, String entry, Matcher message,
        {Set<String> reserved = const {}}) async {
      await expectLater(
        _bundle(dir, entry, reserved: reserved),
        throwsA(isA<BundlerException>()
            .having((e) => e.message, 'message', message)),
      );
    }

    test('un module importé des deux façons est refusé', () async {
      final dir = _project({
        'utils/ui.ks': 'let T = 1\n',
        'features/a.ks': '@use "../utils/ui.ks" as palette\nfn a() { return palette.T }\n',
        'pages/home.ks': '@use "../utils/ui.ks"\n'
            '@use "../features/a.ks" as fa\n'
            'fn probe() { return T }\n',
      });

      await expectRefus(dir, 'pages/home.ks', contains('imported both ways'));
    });

    test('un alias qui désigne deux modules est refusé', () async {
      final dir = _project({
        'a/ui.ks': 'let T = 1\n',
        'b/ui.ks': 'let T = 2\n',
        'features/a.ks': '@use "../a/ui.ks" as palette\nfn a() { return palette.T }\n',
        'pages/home.ks': '@use "../b/ui.ks" as palette\n'
            '@use "../features/a.ks" as fa\n'
            'fn probe() { return palette.T }\n',
      });

      await expectRefus(
          dir, 'pages/home.ks', contains('names two different modules'));
    });

    test('un alias qui recouvre un widget est refusé', () async {
      final dir = _project({
        'utils/ui.ks': 'let T = 1\n',
        'pages/home.ks': '@use "../utils/ui.ks" as Text\n'
            'fn probe() { return Text.T }\n',
      });

      await expectRefus(dir, 'pages/home.ks',
          contains('already a widget or a host namespace'),
          reserved: {'Text', 'Column'});
    });

    test('un alias qui recouvre un namespace de l\'hôte est refusé', () async {
      // `ui` est le namespace du SDK — le module le masquerait pour tout le
      // bundle, et `ui.toast()` disparaîtrait sans un mot.
      final dir = _project({
        'utils/ui.ks': 'let T = 1\n',
        'pages/home.ks': '@use "../utils/ui.ks" as ui\n'
            'fn probe() { return ui.T }\n',
      });

      await expectRefus(dir, 'pages/home.ks',
          contains('already a widget or a host namespace'),
          reserved: kHostGlobals);
    });

    test('un fichier ne peut pas emprunter l\'alias d\'un autre', () async {
      // `home.ks` n'importe pas la palette, mais le bundle étant plat, l'alias
      // y serait résolu quand même. C'est précisément ce qui doit être refusé.
      final dir = _project({
        'utils/ui.ks': 'let T = 1\n',
        'features/a.ks': '@use "../utils/ui.ks" as palette\nfn a() { return palette.T }\n',
        'pages/home.ks': '@use "../features/a.ks" as fa\n'
            'fn probe() { return palette.T }\n',
      });

      await expectRefus(dir, 'pages/home.ks', contains('uses "palette"'));
    });

    test('mais il peut le réimporter sous le même nom', () async {
      final dir = _project({
        'utils/ui.ks': 'let T = 7\n',
        'features/a.ks': '@use "../utils/ui.ks" as palette\nfn a() { return palette.T }\n',
        'pages/home.ks': '@use "../utils/ui.ks" as palette\n'
            '@use "../features/a.ks" as fa\n'
            'fn probe() { return palette.T + fa.a() }\n',
      });

      expect(await _run(await _bundle(dir, 'pages/home.ks')), 14);
    });

    test('les imports circulaires restent refusés', () async {
      final dir = _project({
        'a.ks': '@use "./b.ks" as b\nfn fa() { return b.fb() }\n',
        'b.ks': '@use "./a.ks" as a\nfn fb() { return 1 }\n',
      });

      await expectRefus(dir, 'a.ks', contains('Circular dependency'));
    });
  });
}
