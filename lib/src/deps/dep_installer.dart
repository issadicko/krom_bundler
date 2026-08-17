import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../bundler/bundler.dart' show BundlerException;
import '../bundler/manifest_validator.dart';
import 'deps.dart';

/// Échec d'une opération sur les dépendances, message prêt à afficher.
class DepException implements Exception {
  final String message;
  DepException(this.message);

  @override
  String toString() => message;
}

/// Le nom qu'on déduit de [gitUrl] (dernier segment sans `.git`), ou null
/// s'il ne fait pas un nom de dépendance valide.
String? nameFromUrl(String gitUrl) {
  var base = gitUrl.replaceAll(RegExp(r'/+$'), '');
  base = base.substring(base.lastIndexOf('/') + 1);
  final colon = base.lastIndexOf(':');
  if (colon >= 0) base = base.substring(colon + 1);
  if (base.endsWith('.git')) base = base.substring(0, base.length - 4);
  return kDepNameRe.hasMatch(base) ? base : null;
}

String shortCommit(String commit) =>
    commit.length > 7 ? commit.substring(0, 7) : commit;

/// Installe les dépendances .ks sous `.krom/deps`, via le git du système :
/// l'authentification est celle de l'utilisateur (credential helper), krom
/// ne voit jamais de jeton.
class DepInstaller {
  final String projectDir;

  DepInstaller(this.projectDir);

  ProcessResult _git(List<String> args, {String? workingDirectory}) {
    try {
      return Process.runSync(
        'git',
        args,
        workingDirectory: workingDirectory,
        environment: {
          // Pas de prompt d'identifiants hors TTY : mieux vaut échouer net
          // qu'un `deps get` suspendu en CI.
          if (!stdin.hasTerminal) 'GIT_TERMINAL_PROMPT': '0',
        },
      );
    } on ProcessException {
      throw DepException(
          'git is required to manage .ks dependencies, and was not found on '
          'this machine.');
    }
  }

  String _fail(String head, ProcessResult result) {
    final details = (result.stderr as String).trim();
    return details.isEmpty ? head : '$head\n$details';
  }

  /// La branche par défaut du dépôt distant (pour `add` sans --ref).
  String defaultRef(String gitUrl) {
    final result = _git(['ls-remote', '--symref', gitUrl, 'HEAD']);
    if (result.exitCode == 0) {
      final match = RegExp(r'^ref:\s+refs/heads/(\S+)\s+HEAD', multiLine: true)
          .firstMatch(result.stdout as String);
      if (match != null) return match.group(1)!;
    }
    throw DepException(_fail(
        'Cannot discover the default branch of $gitUrl — pass --ref.', result));
  }

  /// Clone `--depth 1` de [dep] sur sa ref ; rend (clone, commit de HEAD).
  (Directory, String) _fetch(KromDep dep) {
    final tmp = Directory.systemTemp.createTempSync('krom_dep_');
    final clone = _git([
      '-c', 'advice.detachedHead=false', //
      'clone', '--quiet', '--depth', '1', '--branch', dep.ref,
      dep.git, tmp.path,
    ]);
    if (clone.exitCode != 0) {
      tmp.deleteSync(recursive: true);
      throw DepException(_fail(
          'Cannot fetch "${dep.name}" from ${dep.git} at ref "${dep.ref}". '
          'The ref must be an existing branch or tag.',
          clone));
    }
    final rev = _git(['rev-parse', 'HEAD'], workingDirectory: tmp.path);
    if (rev.exitCode != 0) {
      tmp.deleteSync(recursive: true);
      throw DepException(
          _fail('Cannot read the fetched commit of "${dep.name}".', rev));
    }
    return (tmp, (rev.stdout as String).trim());
  }

  /// Installe [dep]. Avec [locked], l'installation doit tomber sur le commit
  /// verrouillé — sinon la ref a bougé et on refuse. Sans [locked], résout
  /// librement (premier get, upgrade). Rend l'entrée de lock effective et si
  /// quelque chose a été fait (déjà conforme → rien, sans réseau).
  (LockEntry, bool) install(KromDep dep, {LockEntry? locked}) {
    final target = depDir(projectDir, dep.name);
    if (locked != null) {
      final marker = DepMarker.read(target);
      if (marker != null && marker.matchesLock(locked)) {
        return (locked, false);
      }
    }

    final (clone, commit) = _fetch(dep);
    try {
      if (locked != null && commit != locked.commit) {
        throw DepException('"${dep.name}": ref "${dep.ref}" now points at '
            '${shortCommit(commit)}, but krom.lock pins '
            '${shortCommit(locked.commit)}. Run `krom deps upgrade '
            '${dep.name}` to accept the new commit.');
      }

      var sourceRoot = clone.path;
      if (dep.path != null) {
        sourceRoot = p.join(clone.path, dep.path);
        if (!Directory(sourceRoot).existsSync()) {
          throw DepException('"${dep.name}": path "${dep.path}" does not '
              'exist in the repository.');
        }
      }

      final targetDir = Directory(target);
      if (targetDir.existsSync()) targetDir.deleteSync(recursive: true);
      targetDir.createSync(recursive: true);
      _copyTree(sourceRoot, target);

      DepMarker(git: dep.git, ref: dep.ref, commit: commit, path: dep.path)
          .write(target);
      _ensureGitignore();
      return (
        LockEntry(git: dep.git, ref: dep.ref, commit: commit, path: dep.path),
        true,
      );
    } finally {
      clone.deleteSync(recursive: true);
    }
  }

  /// Copie récursive, sans `.git` — le dossier installé est une photo, pas
  /// un dépôt imbriqué.
  void _copyTree(String from, String to) {
    for (final entity in Directory(from).listSync()) {
      final name = p.basename(entity.path);
      if (name == '.git') continue;
      final targetPath = p.join(to, name);
      if (entity is Directory) {
        Directory(targetPath).createSync();
        _copyTree(entity.path, targetPath);
      } else if (entity is File) {
        entity.copySync(targetPath);
      }
    }
  }

  /// `.krom/` s'auto-gitignore, même mécanique que le cache projet.
  void _ensureGitignore() {
    final gitignore = File(p.join(projectDir, '.krom', '.gitignore'));
    if (!gitignore.existsSync()) {
      gitignore.parent.createSync(recursive: true);
      gitignore.writeAsStringSync('*\n');
    }
  }
}

/// Le bilan d'un `deps get`.
class GetReport {
  final List<String> installed = [];
  final List<String> upToDate = [];
  final List<String> pruned = [];
}

/// Une ligne de `krom deps status`.
class DepStatusRow {
  final String name;
  final String ref;
  final String? commit;
  final DepStatus status;

  const DepStatusRow({
    required this.name,
    required this.ref,
    required this.commit,
    required this.status,
  });
}

/// Orchestration de get/add/upgrade/status au-dessus de l'installeur.
class DepsService {
  final String projectDir;
  final DepInstaller installer;

  DepsService(this.projectDir) : installer = DepInstaller(projectDir);

  /// Installe tout ce que le manifeste déclare : au commit du lock quand il
  /// vaut encore, en résolvant ce qui manque. Purge les dossiers non
  /// déclarés et réécrit le lock — le lock est une fonction du manifeste.
  GetReport get(Map<String, KromDep> deps) {
    final lock = KromLock.read(projectDir);
    final report = GetReport();
    final entries = <String, LockEntry>{};

    for (final dep in deps.values) {
      final locked = lock.deps[dep.name];
      final usable = locked != null && locked.matchesDep(dep) ? locked : null;
      final (entry, didInstall) = installer.install(dep, locked: usable);
      entries[dep.name] = entry;
      (didInstall ? report.installed : report.upToDate).add(dep.name);
    }

    final root = Directory(depsRoot(projectDir));
    if (root.existsSync()) {
      for (final entity in root.listSync().whereType<Directory>()) {
        final name = p.basename(entity.path);
        if (!deps.containsKey(name)) {
          entity.deleteSync(recursive: true);
          report.pruned.add(name);
        }
      }
    }

    if (entries.isEmpty) {
      final lockFile = KromLock.fileOf(projectDir);
      if (lockFile.existsSync()) lockFile.deleteSync();
    } else {
      KromLock(entries).write(projectDir);
    }
    return report;
  }

  /// Re-résout la ref de [names] (toutes par défaut) et réécrit le lock.
  /// Rend, par dépendance, le commit d'avant (null si aucun) et le nouveau.
  Map<String, (String?, String)> upgrade(
    Map<String, KromDep> deps, {
    List<String> names = const [],
  }) {
    for (final name in names) {
      if (!deps.containsKey(name)) {
        throw DepException('"$name" is not a declared dependency '
            '(declared: ${deps.keys.join(', ')}).');
      }
    }
    final targets = names.isEmpty ? deps.keys.toList() : names;
    final lock = KromLock.read(projectDir);
    final changes = <String, (String?, String)>{};

    for (final name in targets) {
      final before = lock.deps[name]?.commit;
      final (entry, _) = installer.install(deps[name]!);
      lock.deps[name] = entry;
      changes[name] = (before, entry.commit);
    }

    lock.deps.removeWhere((name, _) => !deps.containsKey(name));
    KromLock(lock.deps).write(projectDir);
    return changes;
  }

  /// Déclare, installe et verrouille une dépendance. Le manifeste n'est
  /// réécrit qu'après une installation réussie.
  (KromDep, LockEntry) add(
    String manifestPath, {
    required String url,
    String? ref,
    String? path,
    String? name,
  }) {
    final manifestFile = File(manifestPath);
    final manifest =
        jsonDecode(manifestFile.readAsStringSync()) as Map<String, dynamic>;
    final existing = depsFromManifest(manifest);

    final depName = name ?? nameFromUrl(url);
    if (depName == null) {
      throw DepException(
          'Cannot derive a valid dependency name from "$url" — pass --name.');
    }
    if (existing.containsKey(depName)) {
      throw DepException('"$depName" is already declared. Use '
          '`krom deps upgrade $depName` to refresh it.');
    }

    final resolvedRef = ref ?? installer.defaultRef(url);
    final rawDeps = <String, dynamic>{
      ...?(manifest['dependencies'] as Map?)?.cast<String, dynamic>(),
      depName: {
        'git': url,
        'ref': resolvedRef,
        if (path != null) 'path': path,
      },
    };

    // Les règles du manifeste (nom, collisions, path) valent dès maintenant,
    // pas au prochain build.
    try {
      ManifestValidator.validate({'dependencies': rawDeps});
    } on BundlerException catch (e) {
      throw DepException(e.message);
    }

    final dep = KromDep(name: depName, git: url, ref: resolvedRef, path: path);
    final (entry, _) = installer.install(dep);

    manifest['dependencies'] = rawDeps;
    manifestFile.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(manifest)}\n');

    final lock = KromLock.read(projectDir);
    lock.deps[depName] = entry;
    KromLock(lock.deps).write(projectDir);
    return (dep, entry);
  }

  /// L'état de chaque dépendance déclarée, pour l'affichage.
  List<DepStatusRow> status(Map<String, KromDep> deps) {
    final lock = KromLock.read(projectDir);
    return [
      for (final dep in deps.values)
        DepStatusRow(
          name: dep.name,
          ref: dep.ref,
          commit: lock.deps[dep.name]?.commit,
          status: depStatus(
            dep,
            lock.deps[dep.name],
            DepMarker.read(depDir(projectDir, dep.name)),
          ),
        ),
    ];
  }
}
