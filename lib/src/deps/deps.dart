import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Une dépendance .ks déclarée dans `dependencies` du manifeste : un dépôt
/// git figé sur une ref, installé sous `.krom/deps/<nom>`.
class KromDep {
  final String name;
  final String git;
  final String ref;

  /// Sous-dossier du dépôt servant de racine au paquet (monorepo).
  final String? path;

  const KromDep({
    required this.name,
    required this.git,
    required this.ref,
    this.path,
  });
}

/// Les dépendances déclarées par [manifest], par nom. À appeler après
/// `ManifestValidator.validate` — les entrées malformées sont ignorées ici,
/// la validation les a déjà signalées.
Map<String, KromDep> depsFromManifest(Map<String, dynamic> manifest) {
  final raw = manifest['dependencies'];
  if (raw is! Map) return const {};
  final deps = <String, KromDep>{};
  for (final entry in raw.entries) {
    final name = entry.key.toString();
    final value = entry.value;
    if (value is! Map) continue;
    final git = value['git'];
    final ref = value['ref'];
    if (git is! String || git.isEmpty || ref is! String || ref.isEmpty) {
      continue;
    }
    final path = value['path'];
    deps[name] = KromDep(
      name: name,
      git: git,
      ref: ref,
      path: path is String && path.isNotEmpty ? path : null,
    );
  }
  return deps;
}

/// Dossier d'installation des dépendances du projet.
String depsRoot(String projectDir) => p.join(projectDir, '.krom', 'deps');

/// Dossier d'installation de la dépendance [name].
String depDir(String projectDir, String name) =>
    p.join(depsRoot(projectDir), name);

/// Une entrée de `krom.lock` : la résolution figée d'une dépendance.
class LockEntry {
  final String git;
  final String ref;
  final String commit;
  final String? path;

  const LockEntry({
    required this.git,
    required this.ref,
    required this.commit,
    this.path,
  });

  Map<String, dynamic> toJson() => {
        'git': git,
        'ref': ref,
        'commit': commit,
        if (path != null) 'path': path,
      };

  static LockEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final git = json['git'];
    final ref = json['ref'];
    final commit = json['commit'];
    if (git is! String || ref is! String || commit is! String) return null;
    final path = json['path'];
    return LockEntry(
      git: git,
      ref: ref,
      commit: commit,
      path: path is String ? path : null,
    );
  }

  /// La résolution couvre-t-elle encore ce que [dep] déclare ?
  bool matchesDep(KromDep dep) =>
      git == dep.git && ref == dep.ref && path == dep.path;
}

/// `krom.lock` : les SHA résolus, committé pour des builds reproductibles.
class KromLock {
  static const fileName = 'krom.lock';

  final Map<String, LockEntry> deps;

  KromLock([Map<String, LockEntry>? deps]) : deps = deps ?? {};

  static File fileOf(String projectDir) => File(p.join(projectDir, fileName));

  /// Le lock du projet, vide si le fichier manque ou ne se lit pas.
  static KromLock read(String projectDir) {
    final file = fileOf(projectDir);
    if (!file.existsSync()) return KromLock();
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map) return KromLock();
      final raw = json['deps'];
      if (raw is! Map) return KromLock();
      final deps = <String, LockEntry>{};
      for (final entry in raw.entries) {
        final parsed = LockEntry.fromJson(entry.value);
        if (parsed != null) deps[entry.key.toString()] = parsed;
      }
      return KromLock(deps);
    } catch (_) {
      return KromLock();
    }
  }

  /// Écrit le lock, clés triées pour des diffs stables.
  void write(String projectDir) {
    final names = deps.keys.toList()..sort();
    final json = {
      'version': 1,
      'deps': {for (final name in names) name: deps[name]!.toJson()},
    };
    fileOf(projectDir).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(json)}\n');
  }
}

/// Marqueur `.dep.json` écrit à l'installation : ce qui est réellement dans
/// le dossier. Comparé au lock, il rend l'installation idempotente et le
/// build vérifiable sans réseau.
class DepMarker {
  static const fileName = '.dep.json';

  final String git;
  final String ref;
  final String commit;
  final String? path;

  const DepMarker({
    required this.git,
    required this.ref,
    required this.commit,
    this.path,
  });

  static DepMarker? read(String depDir) {
    final file = File(p.join(depDir, fileName));
    if (!file.existsSync()) return null;
    try {
      final json = jsonDecode(file.readAsStringSync());
      if (json is! Map) return null;
      final git = json['git'];
      final ref = json['ref'];
      final commit = json['commit'];
      if (git is! String || ref is! String || commit is! String) return null;
      final path = json['path'];
      return DepMarker(
        git: git,
        ref: ref,
        commit: commit,
        path: path is String ? path : null,
      );
    } catch (_) {
      return null;
    }
  }

  void write(String depDir) {
    final json = {
      'git': git,
      'ref': ref,
      'commit': commit,
      if (path != null) 'path': path,
    };
    File(p.join(depDir, fileName)).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(json)}\n');
  }

  /// Même contenu installé que ce que [lock] fige ? La ref ne compte pas :
  /// à commit égal, les sources sont les mêmes.
  bool matchesLock(LockEntry lock) =>
      git == lock.git && commit == lock.commit && path == lock.path;
}

/// L'état d'une dépendance déclarée, du point de vue du build.
enum DepStatus {
  /// Installée au commit du lock.
  installed,

  /// Pas d'entrée de lock utilisable (absente, ou le manifeste a changé).
  unlocked,

  /// Verrouillée mais pas installée.
  missing,

  /// Installée, mais pas au commit du lock.
  stale,
}

DepStatus depStatus(KromDep dep, LockEntry? lock, DepMarker? marker) {
  if (lock == null || !lock.matchesDep(dep)) return DepStatus.unlocked;
  if (marker == null) return DepStatus.missing;
  if (!marker.matchesLock(lock)) return DepStatus.stale;
  return DepStatus.installed;
}

/// Ce qui empêche de builder avec [deps] : une ligne par dépendance pas
/// prête, vide quand tout est installé au commit verrouillé. Aucun réseau.
List<String> depProblems(String projectDir, Map<String, KromDep> deps) {
  if (deps.isEmpty) return const [];
  final lock = KromLock.read(projectDir);
  final problems = <String>[];
  for (final dep in deps.values) {
    final marker = DepMarker.read(depDir(projectDir, dep.name));
    switch (depStatus(dep, lock.deps[dep.name], marker)) {
      case DepStatus.installed:
        break;
      case DepStatus.unlocked:
        problems.add('"${dep.name}" is not locked (krom.lock is missing or '
            'out of date with the manifest) — run `krom deps get`.');
      case DepStatus.missing:
        problems.add('"${dep.name}" is not installed — run `krom deps get`.');
      case DepStatus.stale:
        problems.add('"${dep.name}" is installed at a different commit than '
            'krom.lock — run `krom deps get`.');
    }
  }
  return problems;
}
