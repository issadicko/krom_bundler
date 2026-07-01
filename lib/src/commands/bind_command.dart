import 'dart:io';

import 'package:args/command_runner.dart';

import '../backend/backend_client.dart';
import '../backend/project_ref.dart';
import '../utils/config.dart';
import '../utils/logger.dart';

/// `krom bind` — bind a mini-app to one or more super-apps (marketplaces)
/// with a PAT. A mini-app can be bound to several super-apps; `--super-app`
/// is repeatable.
///
/// The app is identified by `--app` (a UUID or a slug), or, when omitted, by
/// the local manifest (`appId` when linked, slug otherwise — with the usual
/// self-healing write-back). An unknown app is an error (publish it first).
class BindCommand extends Command<int> {
  @override
  final name = 'bind';

  @override
  final description = 'Bind this mini-app to super-app(s) (marketplace).';

  BindCommand() {
    argParser
      ..addOption('app',
          help: 'App id (UUID) or slug. Defaults to the manifest identity.')
      ..addMultiOption('super-app',
          abbr: 's',
          help: 'Super-app id(s) (UUID) to bind to. Repeatable.')
      ..addOption('manifest',
          abbr: 'm', help: 'Path to manifest.json', defaultsTo: 'manifest.json');
  }

  @override
  Future<int> run() async {
    final config = KromConfig();
    final remoteUrl = config.remoteUrl;
    final token = config.authToken;

    if (remoteUrl == null || remoteUrl.isEmpty) {
      Logger.error('Remote URL not set.');
      Logger.hint('Use "krom --set-remote=URL" to set the backend URL.');
      return 1;
    }
    if (token == null || token.isEmpty) {
      Logger.error('Not authenticated.');
      Logger.hint('Run "krom login --with-token" with a Personal Access Token.');
      return 1;
    }

    final superAppIds = (argResults!['super-app'] as List<String>)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (superAppIds.isEmpty) {
      Logger.error('At least one --super-app is required.');
      return 1;
    }
    final appRef = (argResults!['app'] as String?)?.trim();
    final manifestPath = argResults!['manifest'] as String;

    final client = BackendClient(baseUrl: remoteUrl, token: token);
    try {
      final String? appId;
      final String label;
      if (appRef != null && appRef.isNotEmpty) {
        appId = ManifestRef.looksLikeUuid(appRef)
            ? appRef
            : (await client.findAppBySlug(appRef))?.id;
        label = appRef;
      } else {
        if (!File(manifestPath).existsSync()) {
          Logger.error('No --app given and no manifest at $manifestPath.');
          return 1;
        }
        final manifest = ManifestRef.load(manifestPath);
        final app = await resolveProjectApp(
          client: client,
          manifest: manifest,
          createIfMissing: false,
        );
        appId = app?.id;
        label = manifest.slug ?? '?';
      }

      if (appId == null) {
        Logger.error('App "$label" not found on the backend.');
        Logger.hint('Publish it first with "krom publish".');
        return 1;
      }

      var step = 0;
      for (final superAppId in superAppIds) {
        Logger.step(++step, superAppIds.length,
            'Binding $label to super-app $superAppId...');
        await client.bind(appId: appId, superAppId: superAppId);
        Logger.success('Bound $label to super-app $superAppId.');
      }
      return 0;
    } on BackendException catch (e) {
      Logger.error(
          e.message + (e.statusCode != null ? ' (${e.statusCode})' : ''));
      if (e.body != null && e.body!.isNotEmpty) Logger.debug(e.body!);
      return 1;
    } catch (e) {
      Logger.error('Bind failed: $e');
      return 1;
    } finally {
      client.close();
    }
  }
}
