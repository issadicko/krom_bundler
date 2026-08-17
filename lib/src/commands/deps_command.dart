import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../bundler/bundler.dart' show BundlerException;
import '../bundler/manifest_validator.dart';
import '../deps/dep_installer.dart';
import '../deps/deps.dart';
import '../utils/logger.dart';

/// `krom deps` — les dépendances .ks du projet.
class DepsCommand extends Command<int> {
  @override
  final name = 'deps';

  @override
  final description =
      "Manage the project's .ks dependencies (status, get, add, upgrade)";

  DepsCommand() {
    addSubcommand(DepsStatusCommand());
    addSubcommand(DepsGetCommand());
    addSubcommand(DepsAddCommand());
    addSubcommand(DepsUpgradeCommand());
  }
}

void _addManifestOption(ArgParser parser) => parser.addOption(
      'manifest',
      abbr: 'm',
      help: 'Path to manifest.json',
      defaultsTo: 'manifest.json',
    );

/// (dossier projet, dépendances déclarées) — ne valide que `dependencies`,
/// les autres champs du manifeste sont l'affaire du build.
(String, Map<String, KromDep>) _loadProject(ArgResults results) {
  final manifestPath = p.absolute(results['manifest'] as String);
  final file = File(manifestPath);
  if (!file.existsSync()) {
    throw DepException('Manifest not found: $manifestPath\n'
        'Run this command from a mini-app project, or pass --manifest.');
  }
  final Map<String, dynamic> manifest;
  try {
    manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  } catch (e) {
    throw DepException('Cannot parse $manifestPath: $e');
  }
  try {
    ManifestValidator.validate({'dependencies': manifest['dependencies']});
  } on BundlerException catch (e) {
    throw DepException(e.message);
  }
  return (p.dirname(manifestPath), depsFromManifest(manifest));
}

int _fail(DepException e) {
  Logger.bundleError(message: e.message);
  return 1;
}

/// `krom deps status` — l'état de chaque dépendance, sans réseau.
class DepsStatusCommand extends Command<int> {
  @override
  final name = 'status';

  @override
  final description =
      'Show each dependency and whether it is installed at the locked commit';

  DepsStatusCommand() {
    _addManifestOption(argParser);
  }

  @override
  Future<int> run() async {
    try {
      final (projectDir, deps) = _loadProject(argResults!);
      if (deps.isEmpty) {
        Logger.info('No dependencies declared.');
        return 0;
      }
      final rows = DepsService(projectDir).status(deps);
      Logger.panel('Dependencies', [
        for (final row in rows)
          (
            row.name,
            '${row.ref}'
                '${row.commit != null ? ' @ ${shortCommit(row.commit!)}' : ''}'
                ' — ${_label(row.status)}',
          ),
      ]);
      final ready = rows.every((row) => row.status == DepStatus.installed);
      if (!ready) Logger.info('Run `krom deps get` to fix the state above.');
      return ready ? 0 : 1;
    } on DepException catch (e) {
      return _fail(e);
    }
  }

  String _label(DepStatus status) => switch (status) {
        DepStatus.installed => 'installed',
        DepStatus.unlocked => 'not locked',
        DepStatus.missing => 'not installed',
        DepStatus.stale => 'differs from krom.lock',
      };
}

/// `krom deps get` — installe le déclaré, au commit verrouillé.
class DepsGetCommand extends Command<int> {
  @override
  final name = 'get';

  @override
  final description = 'Install every declared dependency at its locked commit '
      '(resolving whatever krom.lock does not cover yet)';

  DepsGetCommand() {
    _addManifestOption(argParser);
  }

  @override
  Future<int> run() async {
    try {
      final (projectDir, deps) = _loadProject(argResults!);
      final report = DepsService(projectDir).get(deps);
      if (deps.isEmpty && report.pruned.isEmpty) {
        Logger.info('No dependencies declared.');
        return 0;
      }
      for (final name in report.installed) {
        Logger.success('$name installed');
      }
      for (final name in report.upToDate) {
        Logger.info('$name already up to date');
      }
      for (final name in report.pruned) {
        Logger.info('$name pruned (no longer declared)');
      }
      return 0;
    } on DepException catch (e) {
      return _fail(e);
    }
  }
}

/// `krom deps add` — déclare, installe et verrouille en un geste.
class DepsAddCommand extends Command<int> {
  @override
  final name = 'add';

  @override
  final description = 'Declare a dependency, install it and lock it';

  @override
  String get invocation => 'krom deps add <git-url> [--ref <tag|branch>]';

  DepsAddCommand() {
    _addManifestOption(argParser);
    argParser
      ..addOption('ref',
          help: 'Branch or tag to pin (default: the remote default branch)')
      ..addOption('path',
          help: 'Subdirectory of the repository to install (monorepo)')
      ..addOption('name',
          help: 'Dependency name (default: derived from the URL)');
  }

  @override
  Future<int> run() async {
    final rest = argResults!.rest;
    if (rest.length != 1) {
      usageException('Expected exactly one <git-url>.');
    }
    try {
      final manifestPath = p.absolute(argResults!['manifest'] as String);
      final (projectDir, _) = _loadProject(argResults!);
      final (dep, entry) = DepsService(projectDir).add(
        manifestPath,
        url: rest.first,
        ref: argResults!['ref'] as String?,
        path: argResults!['path'] as String?,
        name: argResults!['name'] as String?,
      );
      Logger.panel(
        'Dependency added',
        [
          ('Name', dep.name),
          ('Ref', dep.ref),
          ('Commit', shortCommit(entry.commit)),
          if (dep.path != null) ('Path', dep.path!),
        ],
        highlight: 'Name',
        footer: 'Import it with @use "${dep.name}/<file>" — krom.lock updated.',
      );
      return 0;
    } on DepException catch (e) {
      return _fail(e);
    }
  }
}

/// `krom deps upgrade` — re-résout les refs et accepte les nouveaux commits.
class DepsUpgradeCommand extends Command<int> {
  @override
  final name = 'upgrade';

  @override
  final description =
      'Re-resolve refs to their current commits and update krom.lock';

  @override
  String get invocation => 'krom deps upgrade [names…]';

  DepsUpgradeCommand() {
    _addManifestOption(argParser);
  }

  @override
  Future<int> run() async {
    try {
      final (projectDir, deps) = _loadProject(argResults!);
      if (deps.isEmpty) {
        Logger.info('No dependencies declared.');
        return 0;
      }
      final changes =
          DepsService(projectDir).upgrade(deps, names: argResults!.rest);
      for (final entry in changes.entries) {
        final (before, after) = entry.value;
        if (before == after) {
          Logger.info('${entry.key} unchanged (${shortCommit(after)})');
        } else if (before == null) {
          Logger.success('${entry.key} locked at ${shortCommit(after)}');
        } else {
          Logger.success('${entry.key} ${shortCommit(before)} → '
              '${shortCommit(after)}');
        }
      }
      return 0;
    } on DepException catch (e) {
      return _fail(e);
    }
  }
}
