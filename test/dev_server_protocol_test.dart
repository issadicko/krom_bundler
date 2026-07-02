import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:krom_bundler/src/bundler/manifest_bundler.dart';
import 'package:krom_bundler/src/server/dev_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The device protocol on `/ws`: raw manifest pushes (historical), plus —
/// for clients that announce themselves with a `hello` frame — dev envelopes
/// (bundle errors) and `log` forwarding printed with the 📱 marker.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('dev_server_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String writeProject({required bool valid}) {
    final manifest = p.join(tmp.path, 'manifest.json');
    File(manifest).writeAsStringSync(jsonEncode({
      'id': 'demo',
      'name': 'Demo',
      'version': '1.0.0',
      'entry': 'home',
      'pages': {
        'home': {'name': 'Home', 'source': 'pages/home.ks'},
      },
    }));
    Directory(p.join(tmp.path, 'pages')).createSync();
    File(p.join(tmp.path, 'pages', 'home.ks')).writeAsStringSync(valid
        ? 'fn build() {\n  return Text("hi")\n}\n'
        : 'fn build( {  broken\n');
    return manifest;
  }

  Future<(DevServer, WebSocket, Stream<dynamic>, List<String>)> boot(
      String manifestPath) async {
    final printed = <String>[];
    final port = 39000 + Random().nextInt(999);
    final server = DevServer(
      manifestBundler: ManifestBundler(),
      manifestPath: manifestPath,
      host: '127.0.0.1',
      port: port,
    );
    await runZoned(
      server.start,
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) => printed.add(line),
      ),
    );
    final ws = await WebSocket.connect('ws://127.0.0.1:$port/ws');
    return (server, ws, ws.asBroadcastStream(), printed);
  }

  test('hello + log frames are printed with the device marker', () async {
    final (server, ws, frames, printed) = await boot(writeProject(valid: true));

    final manifest =
        jsonDecode(await frames.first.timeout(const Duration(seconds: 5)));
    expect(manifest['id'], 'demo');

    ws.add(jsonEncode({'type': 'hello', 'device': 'iPhone Krom Go'}));
    ws.add(jsonEncode(
        {'type': 'log', 'level': 'error', 'device': 'iPhone', 'message': 'boom'}));
    await Future<void>.delayed(const Duration(milliseconds: 400));

    expect(printed.any((l) => l.contains('📱') && l.contains('iPhone Krom Go')),
        isTrue, reason: 'hello line: $printed');
    expect(printed.any((l) => l.contains('📱 [error]') && l.contains('boom')),
        isTrue, reason: 'log line: $printed');

    // Garbage and manifest-only clients don't break anything.
    ws.add('not json');
    await ws.close();
    await server.stop();
  });

  test('a device joining while the bundle is broken gets the error overlay',
      () async {
    final (server, ws, frames, _) = await boot(writeProject(valid: false));

    // Historical first frame (placeholder manifest) — envelope only after hello.
    await frames.first.timeout(const Duration(seconds: 5));
    ws.add(jsonEncode({'type': 'hello', 'device': 'test'}));

    final envelope = jsonDecode(await frames
        .firstWhere((f) => f.toString().contains('krom-dev-error'))
        .timeout(const Duration(seconds: 5)));
    expect(envelope['type'], 'krom-dev-error');
    expect(envelope['message'], isNotEmpty);

    await ws.close();
    await server.stop();
  });
}
