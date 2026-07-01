import 'dart:convert';

import 'package:args/command_runner.dart';

import '../backend/backend_client.dart';
import '../utils/config.dart';
import '../utils/logger.dart';

/// `krom super-apps` — list the tenant's super-apps (id, name, status).
///
/// `--json` emits a machine-readable array on stdout; the VSCode extension
/// uses it to offer a pick-by-name instead of a copy-pasted UUID.
class SuperAppsCommand extends Command<int> {
  @override
  final name = 'super-apps';

  @override
  final description = 'List the super-apps of your tenant.';

  SuperAppsCommand() {
    argParser.addFlag('json',
        negatable: false, help: 'Print a JSON array (for tooling).');
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

    final client =
        BackendClient(baseUrl: config.remoteUrl!, token: config.authToken!);
    try {
      final apps = await client.listSuperApps();

      if (argResults!['json'] as bool) {
        print(jsonEncode([
          for (final a in apps)
            {'id': a.id, 'name': a.name, 'status': a.status},
        ]));
        return 0;
      }

      if (apps.isEmpty) {
        Logger.info('No super-apps on this tenant yet.');
        return 0;
      }
      for (final a in apps) {
        Logger.keyValue(a.name, '${a.id}${a.status != null ? '  [${a.status}]' : ''}');
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
