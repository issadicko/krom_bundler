import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../backend/backend_client.dart';
import '../backend/project_ref.dart';
import '../utils/config.dart';
import '../utils/logger.dart';
import '../utils/project_cache.dart';

/// `krom bindings` — list the super-apps this mini-app is bound to.
///
/// The backend is the source of truth; the result also refreshes the
/// `.krom/project.json` cache (super-app names resolved for display). `--json`
/// emits a machine-readable object for the extension.
class BindingsCommand extends Command<int> {
  @override
  final name = 'bindings';

  @override
  final description = 'List the super-apps this mini-app is bound to.';

  BindingsCommand() {
    argParser
      ..addOption('manifest',
          abbr: 'm', help: 'Path to manifest.json', defaultsTo: 'manifest.json')
      ..addFlag('json',
          negatable: false, help: 'Print a JSON object (for tooling).');
  }

  @override
  Future<int> run() async {
    final config = KromConfig();
    if (config.remoteUrl == null || config.remoteUrl!.isEmpty) {
      Logger.error('Remote URL not set.');
      Logger.hint('Use "krom --set-remote=URL" to set the backend URL.');
      return 1;
    }
    if (!config.isAuthenticated) {
      Logger.error('Not authenticated.');
      Logger.hint('Run "krom login --with-token" with a Personal Access Token.');
      return 1;
    }

    final manifestPath = argResults!['manifest'] as String;
    if (!File(manifestPath).existsSync()) {
      Logger.error('Manifest not found: $manifestPath');
      return 1;
    }

    final manifest = ManifestRef.load(manifestPath);
    final client =
        BackendClient(baseUrl: config.remoteUrl!, token: config.authToken!);
    try {
      final app = await resolveProjectApp(
        client: client,
        manifest: manifest,
        createIfMissing: false,
      );
      if (app == null) {
        Logger.error('App "${manifest.slug}" not found on the backend.');
        Logger.hint('Publish it first with "krom publish" (or "krom link").');
        return 1;
      }

      final bindings = await client.listBindings(appId: app.id);
      // Join super-app names for display (one extra listing, tenant-scoped).
      final names = {
        for (final s in await client.listSuperApps()) s.id: s.name,
      };
      final entries = [
        for (final b in bindings)
          {
            'superAppId': b.superAppId,
            'name': names[b.superAppId] ?? b.superAppId,
            'isActive': b.isActive,
          },
      ];

      ProjectCache(manifest.projectDir)
          .recordBindings(appId: app.id, bindings: entries);

      if (argResults!['json'] as bool) {
        print(jsonEncode({'appId': app.id, 'bindings': entries}));
        return 0;
      }

      if (entries.isEmpty) {
        Logger.info('"${app.slug}" is not bound to any super-app yet.');
        Logger.hint('Bind it with "krom bind --super-app <id>".');
        return 0;
      }
      for (final e in entries) {
        Logger.keyValue('${e['name']}',
            '${e['superAppId']}  ${e['isActive'] == true ? '[active]' : '[inactive]'}');
      }
      return 0;
    } on BackendException catch (e) {
      Logger.error(
          e.message + (e.statusCode != null ? ' (${e.statusCode})' : ''));
      if (e.body != null && e.body!.isNotEmpty) Logger.debug(e.body!);
      return 1;
    } finally {
      client.close();
    }
  }
}
