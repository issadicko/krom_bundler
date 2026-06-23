import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import '../utils/config.dart';
import '../utils/logger.dart';

class DeployCommand extends Command<int> {
  @override
  final name = 'deploy';

  @override
  final description = 'Deploy the generated manifest to Krom backend';

  DeployCommand() {
    argParser
      ..addOption(
        'file',
        abbr: 'f',
        help: 'Path to the bundled manifest file',
        defaultsTo: 'dist/manifest.json',
      )
      ..addOption(
        'app-id',
        abbr: 'a',
        help: 'The target App ID (UUID)',
        mandatory: true,
      );
  }

  @override
  Future<int> run() async {
    final config = KromConfig();
    final remoteUrl = config.remoteUrl;
    final token = config.authToken;

    if (remoteUrl == null) {
      Logger.error('Remote URL not set.');
      Logger.hint('Use "krom --set-remote=URL" to set the backend URL.');
      return 1;
    }

    if (token == null || token.isEmpty) {
      Logger.error('Not authenticated.');
      Logger.hint('Run "krom login --with-token" to authenticate.');
      return 1;
    }

    final filePath = argResults!['file'] as String;
    final appId = argResults!['app-id'] as String;

    final file = File(filePath);
    if (!await file.exists()) {
      Logger.error('Manifest file not found: $filePath');
      Logger.hint('Run "krom build" first to generate the manifest.');
      return 1;
    }

    final content = await file.readAsString();
    Map<String, dynamic> manifest;
    try {
      manifest = jsonDecode(content);
    } catch (e) {
      Logger.error('Invalid JSON in manifest file: $e');
      return 1;
    }

    Logger.step(1, 1, 'Deploying version ${manifest['version']} to $remoteUrl...');

    try {
      final response = await http.post(
        Uri.parse('$remoteUrl/api/v1/apps/$appId/versions'),
        headers: {
          'accept': '*/*',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: content,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body);
        Logger.success('Deployment successful!');
        Logger.keyValue('Version', data['versionString']);
        Logger.keyValue('Status', data['status']);
        Logger.keyValue('Created At', data['createdAt']);
        return 0;
      } else if (response.statusCode == 409) {
        Logger.error('Deployment failed: Version ${manifest['version']} already exists (Conflict).');
        return 1;
      } else {
        Logger.error('Deployment failed: ${response.statusCode} ${response.reasonPhrase}');
        Logger.debug(response.body);
        return 1;
      }
    } catch (e) {
      Logger.error('Connection failed: $e');
      return 1;
    }
  }
}
