import 'dart:convert';
import 'dart:io';

import 'package:args/command_runner.dart';

import '../backend/backend_client.dart';
import '../utils/config.dart';
import '../utils/logger.dart';

/// `krom bind` — bind a mini-app to a super-app (marketplace) with a PAT.
///
/// The app is identified by `--app` (a UUID or a slug), or, when omitted, by the
/// `id` in the local manifest. A slug is resolved to its backend id; an unknown
/// slug is an error (publish it first with `krom publish`).
class BindCommand extends Command<int> {
  @override
  final name = 'bind';

  @override
  final description = 'Bind this mini-app to a super-app (marketplace).';

  BindCommand() {
    argParser
      ..addOption('app',
          help: 'App id (UUID) or slug. Defaults to the manifest "id".')
      ..addOption('super-app',
          abbr: 's', help: 'Super-app id (UUID) to bind to.', mandatory: true)
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

    final superAppId = (argResults!['super-app'] as String).trim();
    var appRef = (argResults!['app'] as String?)?.trim();
    final manifestPath = argResults!['manifest'] as String;

    // Default the app to the manifest slug.
    if (appRef == null || appRef.isEmpty) {
      appRef = _slugFromManifest(manifestPath);
      if (appRef == null) {
        Logger.error('No --app given and manifest.json has no "id".');
        return 1;
      }
    }

    final client = BackendClient(baseUrl: remoteUrl, token: token);
    try {
      final appId = _looksLikeUuid(appRef)
          ? appRef
          : (await client.findAppBySlug(appRef))?.id;

      if (appId == null) {
        Logger.error('App "$appRef" not found on the backend.');
        Logger.hint('Publish it first with "krom publish".');
        return 1;
      }

      Logger.step(1, 1, 'Binding $appRef to super-app $superAppId...');
      await client.bind(appId: appId, superAppId: superAppId);
      Logger.success('Bound $appRef to super-app $superAppId.');
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

  String? _slugFromManifest(String path) {
    try {
      final m = jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
      final slug = m['id']?.toString();
      return (slug != null && slug.isNotEmpty) ? slug : null;
    } catch (_) {
      return null;
    }
  }

  static final _uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  bool _looksLikeUuid(String v) => _uuid.hasMatch(v);
}
