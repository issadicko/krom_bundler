import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:krom_bundler/src/bundler/asset_packager.dart';

/// Locks the wire contract that `krom deploy` uses for a ZIP package:
/// `POST /api/v1/apps/{appId}/versions` as `multipart/form-data` with a
/// `version` text part and a `package` file part, authenticated via a Bearer
/// token. We exercise the exact `http` APIs the command builds the request
/// with, against a throwaway local server.
void main() {
  group('deploy multipart contract', () {
    test('sends version + package parts with Bearer auth to the right path',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      final captured = Completer<Map<String, dynamic>>();
      server.listen((req) async {
        final bytes = await req.fold<List<int>>([], (b, d) => b..addAll(d));
        final body = utf8.decode(bytes, allowMalformed: true);
        final ct = req.headers.contentType?.toString() ?? '';
        captured.complete({
          'method': req.method,
          'path': req.uri.path,
          'auth': req.headers.value('authorization'),
          'isMultipart': ct.contains('multipart/form-data'),
          'hasVersionPart': body.contains('name="version"'),
          'hasPackagePart': body.contains('name="package"'),
          'versionValue': body.contains('\r\n\r\n3.1.4'),
        });
        req.response
          ..statusCode = 201
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({
            'versionString': '3.1.4',
            'status': 'DRAFT',
            'createdAt': 'now',
          }));
        await req.response.close();
      });

      final uri = Uri.parse(
          'http://${server.address.host}:${server.port}/api/v1/apps/APP/versions');

      final request = http.MultipartRequest('POST', uri)
        ..headers['accept'] = '*/*'
        ..headers['Authorization'] = 'Bearer krom_pat_test'
        ..fields['version'] = '3.1.4'
        ..files.add(http.MultipartFile.fromBytes(
          'package',
          utf8.encode('PK-FAKE'),
          filename: 'APP__3.1.4.zip',
          contentType: MediaType('application', 'zip'),
        ));

      final resp = await http.Response.fromStream(await request.send());
      final seen = await captured.future;

      expect(resp.statusCode, 201);
      expect(seen['method'], 'POST');
      expect(seen['path'], '/api/v1/apps/APP/versions');
      expect(seen['auth'], 'Bearer krom_pat_test');
      expect(seen['isMultipart'], isTrue);
      expect(seen['hasVersionPart'], isTrue);
      expect(seen['hasPackagePart'], isTrue);
      expect(seen['versionValue'], isTrue);
    });

    test('version is recoverable from app.json inside a real package',
        () async {
      final tmp = Directory.systemTemp.createTempSync('krom_deploy_');
      addTearDown(() => tmp.deleteSync(recursive: true));

      final result = await AssetPackager.build(
        compiledManifest: {
          'id': 'com.example.app',
          'name': 'App',
          'version': '7.7.7',
          'pages': {
            'home': {'name': 'Home', 'script': '...'},
          },
        },
        projectDir: tmp.path,
      );

      final zipPath =
          p.join(tmp.path, AssetPackager.packageFileName('com.example.app', '7.7.7'));
      File(zipPath).writeAsBytesSync(result.zipBytes);

      // Mirror DeployCommand._versionFromZip: read version out of app.json.
      final archive = ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());
      final appJsonFile = archive.firstWhere((f) => f.name == 'app.json');
      final appJson = jsonDecode(utf8.decode(appJsonFile.content as List<int>))
          as Map<String, dynamic>;
      expect(appJson['version'], '7.7.7');
      expect(p.basename(zipPath), 'com.example.app__7.7.7.zip');
    });
  });
}
