import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:krom_bundler/src/bundler/bundler.dart';
import 'package:krom_bundler/src/bundler/manifest_validator.dart';
import 'package:krom_bundler/src/deps/deps.dart';
import 'package:krom_bundler/src/libs/known_libs.dart';

Directory _tempDir() {
  final dir = Directory.systemTemp.createTempSync('krom_deps_');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// Le message agrégé du validateur, ou null quand [manifest] passe.
String? _validationError(Map<String, dynamic> manifest) {
  try {
    ManifestValidator.validate(manifest);
    return null;
  } on BundlerException catch (e) {
    return e.message;
  }
}

Map<String, dynamic> _manifestWith(Object? dependencies) => {
      'id': 't',
      'name': 'T',
      'version': '1.0.0',
      'pages': {
        'home': {'name': 'Home', 'source': 'pages/home.ks'},
      },
      'dependencies': dependencies,
    };

const _dep = {'git': 'https://git.example/ks-money.git', 'ref': 'v1.0.0'};

void main() {
  group('validation de dependencies', () {
    test('une entrée valide passe', () {
      expect(_validationError(_manifestWith({'money': _dep})), isNull);
      expect(
          _validationError(_manifestWith({
            'ui-kit': {..._dep, 'path': 'packages/ui-kit'},
          })),
          isNull);
    });

    test('dependencies doit être un objet', () {
      expect(_validationError(_manifestWith(['money'])),
          contains('"dependencies" must be an object'));
    });

    test('les noms invalides sont refusés', () {
      for (final name in ['Money', '1money', 'mon ey', '-money']) {
        expect(_validationError(_manifestWith({name: _dep})),
            contains('not a valid dependency name'),
            reason: name);
      }
    });

    test('un nom de pack natif est refusé', () {
      final pack = KnownLibs.packs.first;
      expect(_validationError(_manifestWith({pack: _dep})),
          contains('collides with the "$pack" native pack'));
    });

    test('un namespace hôte est refusé', () {
      expect(_validationError(_manifestWith({'device': _dep})),
          contains('collides with the "device" host namespace'));
    });

    test('git et ref sont requis', () {
      final error = _validationError(_manifestWith({
        'money': {'git': _dep['git']},
      }));
      expect(error, contains('dependencies.money.ref" is required'));

      expect(
          _validationError(_manifestWith({
            'money': {'git': '', 'ref': 'v1'},
          })),
          contains('must be a non-empty string'));
    });

    test('une clé inconnue est signalée', () {
      expect(
          _validationError(_manifestWith({
            'money': {..._dep, 'branch': 'main'},
          })),
          contains('dependencies.money.branch" is not a recognised property'));
    });

    test('path doit rester relatif au dépôt', () {
      expect(
          _validationError(_manifestWith({
            'money': {..._dep, 'path': '/abs'},
          })),
          contains('must be a relative path'));
      expect(
          _validationError(_manifestWith({
            'money': {..._dep, 'path': 'a/../../b'},
          })),
          contains('must be a relative path'));
    });
  });

  group('depsFromManifest', () {
    test('lit les entrées valides et ignore le reste', () {
      final deps = depsFromManifest(_manifestWith({
        'money': _dep,
        'broken': {'git': 'x'},
      }));
      expect(deps.keys, ['money']);
      expect(deps['money']!.git, _dep['git']);
      expect(deps['money']!.ref, 'v1.0.0');
      expect(deps['money']!.path, isNull);
    });

    test('sans dependencies : vide', () {
      expect(depsFromManifest({'id': 't'}), isEmpty);
    });
  });

  group('krom.lock', () {
    test('absent : lock vide', () {
      expect(KromLock.read(_tempDir().path).deps, isEmpty);
    });

    test('aller-retour, clés triées', () {
      final dir = _tempDir();
      KromLock({
        'zeta': const LockEntry(git: 'g', ref: 'r', commit: 'c2'),
        'alpha':
            const LockEntry(git: 'g', ref: 'r', commit: 'c1', path: 'pkg/a'),
      }).write(dir.path);

      final content = KromLock.fileOf(dir.path).readAsStringSync();
      expect(content.indexOf('alpha'), lessThan(content.indexOf('zeta')));

      final lock = KromLock.read(dir.path);
      expect(lock.deps.keys.toSet(), {'alpha', 'zeta'});
      expect(lock.deps['alpha']!.commit, 'c1');
      expect(lock.deps['alpha']!.path, 'pkg/a');
    });

    test('fichier illisible : lock vide', () {
      final dir = _tempDir();
      KromLock.fileOf(dir.path).writeAsStringSync('pas du json');
      expect(KromLock.read(dir.path).deps, isEmpty);
    });
  });

  group('.dep.json', () {
    test('absent : null', () {
      expect(DepMarker.read(_tempDir().path), isNull);
    });

    test('aller-retour', () {
      final dir = _tempDir();
      const DepMarker(git: 'g', ref: 'v1', commit: 'abc', path: 'pkg')
          .write(dir.path);
      final marker = DepMarker.read(dir.path)!;
      expect(marker.git, 'g');
      expect(marker.commit, 'abc');
      expect(marker.path, 'pkg');
    });
  });

  group('depStatus / depProblems', () {
    const dep = KromDep(name: 'money', git: 'g', ref: 'v1');
    const lock = LockEntry(git: 'g', ref: 'v1', commit: 'abc');

    test('les quatre états', () {
      const marker = DepMarker(git: 'g', ref: 'v1', commit: 'abc');
      expect(depStatus(dep, null, null), DepStatus.unlocked);
      expect(
          depStatus(
              dep, const LockEntry(git: 'g', ref: 'v2', commit: 'abc'), null),
          DepStatus.unlocked,
          reason: 'le manifeste a changé depuis la résolution');
      expect(depStatus(dep, lock, null), DepStatus.missing);
      expect(
          depStatus(
              dep, lock, const DepMarker(git: 'g', ref: 'v1', commit: 'old')),
          DepStatus.stale);
      expect(depStatus(dep, lock, marker), DepStatus.installed);
    });

    test('la ref du marqueur ne compte pas, le commit si', () {
      expect(
          depStatus(dep, lock,
              const DepMarker(git: 'g', ref: 'autre', commit: 'abc')),
          DepStatus.installed);
    });

    test('depProblems nomme la commande à lancer', () {
      final dir = _tempDir();
      final problems = depProblems(dir.path, {'money': dep});
      expect(problems, hasLength(1));
      expect(problems.first, contains('krom deps get'));
    });

    test('depProblems : vide quand tout est installé', () {
      final dir = _tempDir();
      KromLock({'money': lock}).write(dir.path);
      final installDir = depDir(dir.path, 'money');
      Directory(installDir).createSync(recursive: true);
      const DepMarker(git: 'g', ref: 'v1', commit: 'abc').write(installDir);
      expect(depProblems(dir.path, {'money': dep}), isEmpty);
    });
  });

  test('depDir pointe sous .krom/deps', () {
    expect(depDir('/proj', 'money'), p.join('/proj', '.krom', 'deps', 'money'));
  });
}
