import 'dart:io';

import 'package:args/command_runner.dart';

import '../backend/backend_client.dart';
import '../backend/project_ref.dart';
import '../utils/config.dart';
import '../utils/logger.dart';

/// `krom link` — attach the local project to its backend app and write the
/// canonical `appId` into `manifest.json`.
///
/// Recovery path for projects created offline (or cloned before the manifest
/// carried an `appId`): resolves by slug, creates the app when it doesn't
/// exist yet (unless `--no-create`), and self-heals a stale `appId`.
class LinkCommand extends Command<int> {
  @override
  final name = 'link';

  @override
  final description =
      'Link this project to its backend app (writes "appId" into manifest.json).';

  LinkCommand() {
    argParser
      ..addOption('manifest',
          abbr: 'm', help: 'Path to manifest.json', defaultsTo: 'manifest.json')
      ..addFlag('create',
          help: 'Create the app on the backend when the slug is unknown.',
          defaultsTo: true);
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
      Logger.hint('Run "krom init <name>" to scaffold a project.');
      return 1;
    }

    final manifest = ManifestRef.load(manifestPath);
    final client =
        BackendClient(baseUrl: config.remoteUrl!, token: config.authToken!);
    try {
      final app = await resolveProjectApp(
        client: client,
        manifest: manifest,
        createIfMissing: argResults!['create'] as bool,
      );
      if (app == null) {
        Logger.error('App "${manifest.slug}" not found on the backend.');
        Logger.hint('Drop --no-create to create it, or publish with "krom publish".');
        return 1;
      }
      Logger.success('Linked to ${app.name} (${app.id}).');
      return 0;
    } on BackendException catch (e) {
      Logger.error(
          e.message + (e.statusCode != null ? ' (${e.statusCode})' : ''));
      if (e.body != null && e.body!.isNotEmpty) Logger.debug(e.body!);
      return 1;
    } catch (e) {
      Logger.error('Link failed: $e');
      return 1;
    } finally {
      client.close();
    }
  }
}
