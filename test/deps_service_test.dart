import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:krom_bundler/src/deps/dep_installer.dart';
import 'package:krom_bundler/src/deps/deps.dart';

Directory _temp(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  return dir;
}

ProcessResult _git(List<String> args, String cwd) {
  final result = Process.runSync(
    'git',
    ['-c', 'user.name=t', '-c', 'user.email=t@t', ...args],
    workingDirectory: cwd,
  );
  expect(result.exitCode, 0, reason: 'git ${args.join(' ')}\n${result.stderr}');
  return result;
}

/// Un dépôt git jetable : [files] committés sur main, taggés [tag].
/// Rend (url file://, dossier, commit).
(String, Directory, String) _gitRepo(Map<String, String> files,
    {String tag = 'v1'}) {
  final dir = _temp('krom_gitfix_');
  files.forEach((relative, content) {
    final file = File(p.join(dir.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  });
  _git(['init', '-q', '-b', 'main'], dir.path);
  _git(['add', '.'], dir.path);
  _git(['commit', '-qm', 'init'], dir.path);
  _git(['tag', tag], dir.path);
  final head = (_git(['rev-parse', 'HEAD'], dir.path).stdout as String).trim();
  return ('file://${dir.path}', dir, head);
}

/// Un commit de plus sur main ; rend le nouveau HEAD.
String _commitMore(Directory repo, Map<String, String> files) {
  files.forEach((relative, content) {
    File(p.join(repo.path, relative)).writeAsStringSync(content);
  });
  _git(['add', '.'], repo.path);
  _git(['commit', '-qm', 'more'], repo.path);
  return (_git(['rev-parse', 'HEAD'], repo.path).stdout as String).trim();
}

void main() {
  group('nameFromUrl', () {
    test('formes https et scp', () {
      expect(nameFromUrl('https://gitlab.orange.bf/krom/ks-money.git'),
          'ks-money');
      expect(nameFromUrl('https://github.com/x/ks-money'), 'ks-money');
      expect(nameFromUrl('git@gitlab.orange.bf:krom/ks-money.git'), 'ks-money');
      expect(nameFromUrl('https://x/Bad Name.git'), isNull);
    });
  });

  group('DepsService.get', () {
    test('installe, marque, verrouille, gitignore', () {
      final (url, _, head) = _gitRepo({'lib.ks': 'fn un() { return 1 }\n'});
      final project = _temp('krom_proj_');
      final deps = {'money': KromDep(name: 'money', git: url, ref: 'v1')};

      final report = DepsService(project.path).get(deps);

      expect(report.installed, ['money']);
      final installed = depDir(project.path, 'money');
      expect(File(p.join(installed, 'lib.ks')).existsSync(), isTrue);
      expect(Directory(p.join(installed, '.git')).existsSync(), isFalse);
      expect(DepMarker.read(installed)!.commit, head);
      expect(KromLock.read(project.path).deps['money']!.commit, head);
      expect(
          File(p.join(project.path, '.krom', '.gitignore')).readAsStringSync(),
          '*\n');
    });

    test('déjà conforme : rien à faire, et sans réseau', () {
      final (url, repo, _) = _gitRepo({'lib.ks': 'let X = 1\n'});
      final project = _temp('krom_proj_');
      final deps = {'money': KromDep(name: 'money', git: url, ref: 'v1')};
      final service = DepsService(project.path);
      service.get(deps);

      // Le dépôt source disparaît : si le second get réseaute, il échoue.
      repo.deleteSync(recursive: true);
      final report = service.get(deps);

      expect(report.upToDate, ['money']);
      expect(report.installed, isEmpty);
    });

    test('path: installe le sous-dossier comme racine', () {
      final (url, _, _) = _gitRepo({
        'packages/kit/ui.ks': 'let K = 1\n',
        'autre.ks': 'let A = 1\n',
      });
      final project = _temp('krom_proj_');
      DepsService(project.path).get({
        'kit': KromDep(name: 'kit', git: url, ref: 'v1', path: 'packages/kit'),
      });

      final installed = depDir(project.path, 'kit');
      expect(File(p.join(installed, 'ui.ks')).existsSync(), isTrue);
      expect(File(p.join(installed, 'autre.ks')).existsSync(), isFalse);
      expect(DepMarker.read(installed)!.path, 'packages/kit');
    });

    test('la ref a bougé : refus net qui nomme upgrade', () {
      final (url, repo, _) = _gitRepo({'lib.ks': 'let X = 1\n'});
      final project = _temp('krom_proj_');
      final deps = {'money': KromDep(name: 'money', git: url, ref: 'main')};
      final service = DepsService(project.path);
      service.get(deps);

      _commitMore(repo, {'lib.ks': 'let X = 2\n'});
      // Installation perdue (autre machine, clean…) : la réinstallation doit
      // retomber sur le commit du lock — la branche ne l'a plus en tête.
      Directory(depDir(project.path, 'money')).deleteSync(recursive: true);

      expect(
          () => service.get(deps),
          throwsA(isA<DepException>().having((e) => e.message, 'message',
              contains('krom deps upgrade money'))));
    });

    test('purge un dossier qui n\'est plus déclaré', () {
      final (url, _, _) = _gitRepo({'lib.ks': 'let X = 1\n'});
      final project = _temp('krom_proj_');
      final orphan = Directory(depDir(project.path, 'orphan'))
        ..createSync(recursive: true);
      File(p.join(orphan.path, 'x.ks')).writeAsStringSync('let O = 1\n');

      final report = DepsService(project.path)
          .get({'money': KromDep(name: 'money', git: url, ref: 'v1')});

      expect(report.pruned, ['orphan']);
      expect(orphan.existsSync(), isFalse);
    });

    test('plus aucune dépendance : purge tout et retire le lock', () {
      final (url, _, _) = _gitRepo({'lib.ks': 'let X = 1\n'});
      final project = _temp('krom_proj_');
      final service = DepsService(project.path);
      service.get({'money': KromDep(name: 'money', git: url, ref: 'v1')});

      final report = service.get({});

      expect(report.pruned, ['money']);
      expect(KromLock.fileOf(project.path).existsSync(), isFalse);
    });
  });

  group('DepsService.upgrade', () {
    test('accepte le nouveau commit et met le lock à jour', () {
      final (url, repo, head1) = _gitRepo({'lib.ks': 'let X = 1\n'});
      final project = _temp('krom_proj_');
      final deps = {'money': KromDep(name: 'money', git: url, ref: 'main')};
      final service = DepsService(project.path);
      service.get(deps);

      final head2 = _commitMore(repo, {'lib.ks': 'let X = 2\n'});
      final changes = service.upgrade(deps);

      expect(changes['money'], (head1, head2));
      expect(KromLock.read(project.path).deps['money']!.commit, head2);
      expect(
          File(p.join(depDir(project.path, 'money'), 'lib.ks'))
              .readAsStringSync(),
          'let X = 2\n');
    });

    test('un nom non déclaré est une erreur', () {
      final project = _temp('krom_proj_');
      expect(
          () => DepsService(project.path).upgrade(
              {'money': const KromDep(name: 'money', git: 'g', ref: 'v1')},
              names: ['autre']),
          throwsA(isA<DepException>().having((e) => e.message, 'message',
              contains('not a declared dependency'))));
    });
  });

  group('DepsService.add', () {
    File writeManifest(Directory project) {
      final file = File(p.join(project.path, 'manifest.json'));
      file.writeAsStringSync('''
{
  "id": "t",
  "name": "T",
  "version": "1.0.0",
  "pages": {}
}
''');
      return file;
    }

    test('installe puis écrit manifeste et lock', () {
      final (url, _, head) = _gitRepo({'lib.ks': 'let X = 1\n'});
      final project = _temp('krom_proj_');
      final manifest = writeManifest(project);

      final (dep, entry) = DepsService(project.path)
          .add(manifest.path, url: url, ref: 'v1', name: 'money');

      expect(dep.ref, 'v1');
      expect(entry.commit, head);
      final written =
          jsonDecode(manifest.readAsStringSync()) as Map<String, dynamic>;
      expect(written['dependencies'], {
        'money': {'git': url, 'ref': 'v1'},
      });
      expect(written['id'], 't', reason: 'le reste du manifeste survit');
      expect(KromLock.read(project.path).deps['money']!.commit, head);
      expect(File(p.join(depDir(project.path, 'money'), 'lib.ks')).existsSync(),
          isTrue);
    });

    test('sans --ref : la branche par défaut du dépôt', () {
      final (url, _, head) = _gitRepo({'lib.ks': 'let X = 1\n'});
      final project = _temp('krom_proj_');
      final manifest = writeManifest(project);

      final (dep, entry) =
          DepsService(project.path).add(manifest.path, url: url, name: 'money');

      expect(dep.ref, 'main');
      expect(entry.commit, head);
    });

    test('refuse un doublon et un nom réservé, sans toucher au manifeste', () {
      final (url, _, _) = _gitRepo({'lib.ks': 'let X = 1\n'});
      final project = _temp('krom_proj_');
      final manifest = writeManifest(project);
      final service = DepsService(project.path);
      service.add(manifest.path, url: url, ref: 'v1', name: 'money');
      final snapshot = manifest.readAsStringSync();

      expect(
          () => service.add(manifest.path, url: url, ref: 'v1', name: 'money'),
          throwsA(isA<DepException>().having(
              (e) => e.message, 'message', contains('already declared'))));
      expect(
          () => service.add(manifest.path, url: url, ref: 'v1', name: 'device'),
          throwsA(isA<DepException>().having(
              (e) => e.message, 'message', contains('host namespace'))));
      expect(manifest.readAsStringSync(), snapshot);
    });
  });

  group('DepsService.status', () {
    test('reflète installé, puis manquant après suppression', () {
      final (url, _, head) = _gitRepo({'lib.ks': 'let X = 1\n'});
      final project = _temp('krom_proj_');
      final deps = {'money': KromDep(name: 'money', git: url, ref: 'v1')};
      final service = DepsService(project.path);
      service.get(deps);

      var rows = service.status(deps);
      expect(rows.single.status, DepStatus.installed);
      expect(rows.single.commit, head);

      Directory(depDir(project.path, 'money')).deleteSync(recursive: true);
      rows = service.status(deps);
      expect(rows.single.status, DepStatus.missing);
    });
  });

  group('DepInstaller.defaultRef', () {
    test('découvre la branche par défaut', () {
      final (url, _, _) = _gitRepo({'lib.ks': 'let X = 1\n'});
      expect(DepInstaller(_temp('krom_proj_').path).defaultRef(url), 'main');
    });
  });
}
