import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import '../utils/config.dart';
import '../utils/logger.dart';

class DeployCommand extends Command<int> {
  @override
  final name = 'deploy';

  @override
  final description = 'Deploy the generated package to Krom backend';

  DeployCommand() {
    argParser
      ..addOption(
        'file',
        abbr: 'f',
        help: 'Path to the version package (.zip) or bundled manifest (.json). '
            'Defaults to the most recent package in dist/, falling back to '
            'dist/manifest.json.',
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

    final appId = argResults!['app-id'] as String;
    final filePath = (argResults!['file'] as String?) ?? _defaultFile();

    final file = File(filePath);
    if (!await file.exists()) {
      Logger.error('Package/manifest file not found: $filePath');
      Logger.hint('Run "krom build" first to generate the package.');
      return 1;
    }

    final uri = Uri.parse('$remoteUrl/api/v1/apps/$appId/versions');

    // A .zip is the signed-ready package: upload as multipart/form-data with a
    // "package" file part and a "version" text part. A .json is a bare manifest
    // and is sent as the legacy JSON body for backward compatibility.
    if (_isZip(filePath)) {
      return _deployPackage(uri, file, token, remoteUrl);
    }
    return _deployManifestJson(uri, file, token, remoteUrl);
  }

  /// Upload the ZIP package via multipart/form-data.
  Future<int> _deployPackage(
    Uri uri,
    File zip,
    String token,
    String remoteUrl,
  ) async {
    final bytes = await zip.readAsBytes();
    final version = _versionFromZip(bytes);
    if (version == null) {
      Logger.error('Could not read "version" from app.json inside the package.');
      Logger.hint('Rebuild with "krom build" to regenerate a valid package.');
      return 1;
    }

    Logger.step(1, 1, 'Deploying version $version to $remoteUrl...');
    Logger.keyValue('Package', p.basename(zip.path));
    Logger.keyValue('Size', Logger.formatSize(bytes.length));

    try {
      final request = http.MultipartRequest('POST', uri)
        ..headers['accept'] = '*/*'
        ..headers['Authorization'] = 'Bearer $token'
        ..fields['version'] = version
        ..files.add(http.MultipartFile.fromBytes(
          'package',
          bytes,
          filename: p.basename(zip.path),
          contentType: MediaType('application', 'zip'),
        ));

      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      return _handleResponse(response, version);
    } catch (e) {
      Logger.error('Connection failed: $e');
      return 1;
    }
  }

  /// Legacy path: POST the raw manifest JSON as the request body.
  Future<int> _deployManifestJson(
    Uri uri,
    File file,
    String token,
    String remoteUrl,
  ) async {
    final content = await file.readAsString();
    Map<String, dynamic> manifest;
    try {
      manifest = jsonDecode(content) as Map<String, dynamic>;
    } catch (e) {
      Logger.error('Invalid JSON in manifest file: $e');
      return 1;
    }

    final version = manifest['version']?.toString() ?? 'unknown';
    Logger.step(1, 1, 'Deploying version $version to $remoteUrl...');

    try {
      final response = await http.post(
        uri,
        headers: {
          'accept': '*/*',
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: content,
      );
      return _handleResponse(response, version);
    } catch (e) {
      Logger.error('Connection failed: $e');
      return 1;
    }
  }

  /// Map the backend response to a CLI exit code and user-facing output.
  int _handleResponse(http.Response response, String version) {
    if (response.statusCode == 200 || response.statusCode == 201) {
      Logger.success('Deployment successful!');
      try {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['versionString'] != null) {
          Logger.keyValue('Version', '${data['versionString']}');
        }
        if (data['status'] != null) {
          Logger.keyValue('Status', '${data['status']}');
        }
        if (data['createdAt'] != null) {
          Logger.keyValue('Created At', '${data['createdAt']}');
        }
      } catch (_) {
        // Non-JSON success body: nothing more to show.
      }
      return 0;
    } else if (response.statusCode == 409) {
      Logger.error('Deployment failed: Version $version already exists '
          '(Conflict).');
      return 1;
    } else {
      Logger.error('Deployment failed: ${response.statusCode} '
          '${response.reasonPhrase}');
      Logger.debug(response.body);
      return 1;
    }
  }

  /// Read the `version` field from `app.json` inside the ZIP [bytes].
  String? _versionFromZip(List<int> bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      for (final f in archive) {
        if (f.isFile && f.name == 'app.json') {
          final json = jsonDecode(utf8.decode(f.content as List<int>))
              as Map<String, dynamic>;
          return json['version']?.toString();
        }
      }
    } catch (_) {
      // Fall through to null on any decode error.
    }
    return null;
  }

  bool _isZip(String path) => p.extension(path).toLowerCase() == '.zip';

  /// Default deploy target: the newest `*.zip` in `dist/`, else
  /// `dist/manifest.json`.
  String _defaultFile() {
    final dist = Directory('dist');
    if (dist.existsSync()) {
      final zips = dist
          .listSync()
          .whereType<File>()
          .where((f) => _isZip(f.path))
          .toList()
        ..sort((a, b) =>
            b.statSync().modified.compareTo(a.statSync().modified));
      if (zips.isNotEmpty) return zips.first.path;
    }
    return p.join('dist', 'manifest.json');
  }
}
