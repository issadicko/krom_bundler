import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:krom_bundler/src/bundler/manifest_bundler.dart';
import 'package:krom_bundler/src/server/dev_server.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The served preview page embeds the dev head scripts: SW cleanup and the
/// focus guard that stops the Flutter engine from yanking keyboard focus out
/// of the editor on boot/hot reload (VSCode device-preview webview, background
/// browser tabs).
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('dev_server_focus'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String writeProject() {
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
    File(p.join(tmp.path, 'pages', 'home.ks'))
        .writeAsStringSync('fn build() {\n  return Text("hi")\n}\n');
    return manifest;
  }

  test('index.html is served with the focus guard and SW cleanup injected',
      () async {
    final port = 39000 + Random().nextInt(999);
    final server = DevServer(
      manifestBundler: ManifestBundler(),
      manifestPath: writeProject(),
      host: '127.0.0.1',
      port: port,
    );
    await runZoned(
      server.start,
      zoneSpecification: ZoneSpecification(
        print: (self, parent, zone, line) {},
      ),
    );

    final client = HttpClient();
    try {
      final req =
          await client.getUrl(Uri.parse('http://127.0.0.1:$port/index.html'));
      final res = await req.close();
      final html = await res.transform(utf8.decoder).join();

      expect(res.statusCode, 200);
      // Focus guard: programmatic focus is patched…
      expect(html, contains('HTMLElement.prototype.focus'));
      // …and only honored on user activation / an already-focused page.
      expect(html, contains('document.hasFocus()'));
      // SW cleanup still there.
      expect(html, contains('serviceWorker'));
      // Injected inside <head>, before the page's own scripts.
      final head = html.indexOf('<head');
      final guard = html.indexOf('HTMLElement.prototype.focus');
      expect(head, greaterThanOrEqualTo(0));
      expect(guard, greaterThan(head));
    } finally {
      client.close(force: true);
      await server.stop();
    }
  });
}
