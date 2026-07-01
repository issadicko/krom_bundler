import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:watcher/watcher.dart';
import 'package:path/path.dart' as p;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../bundler/bundler.dart';
import '../bundler/manifest_bundler.dart';
import '../preview/embedded_preview.dart';
import '../utils/logger.dart';

/// A self-healing no-op service worker served in place of Flutter's
/// `flutter_service_worker.js`. On activation it clears every cache, unregisters
/// itself, and reloads any controlled pages once — so a previously-installed SW
/// that was serving stale/blank cached responses is fully torn down and the page
/// reloads fresh from the network.
const String _noopServiceWorkerJs = '''
// Krom dev: self-healing no-op service worker. Flutter's real SW serves the
// preview from cache — under the dev server that cache goes stale and the page
// renders blank with no network requests. Nuke caches + unregister + reload.
self.addEventListener('install', function (e) { self.skipWaiting(); });
self.addEventListener('activate', function (e) {
  e.waitUntil((async function () {
    try {
      var keys = await caches.keys();
      await Promise.all(keys.map(function (k) { return caches.delete(k); }));
    } catch (_) {}
    try { await self.registration.unregister(); } catch (_) {}
    try {
      var wins = await self.clients.matchAll({ type: 'window' });
      wins.forEach(function (c) { c.navigate(c.url); });
    } catch (_) {}
  })());
});
''';

/// Page-side cleanup injected into every served `index.html`: unregisters any
/// service worker and clears caches on load. Runs in the page context (not a
/// SW), so it kills a stuck SW as soon as one fresh network load of index.html
/// happens — no dependency on the browser re-fetching the SW script.
const String _swCleanupHeadScript = '''
<script>
(function () {
  try {
    if ('serviceWorker' in navigator) {
      navigator.serviceWorker.getRegistrations()
        .then(function (rs) { rs.forEach(function (r) { r.unregister(); }); })
        .catch(function () {});
    }
    if (window.caches && caches.keys) {
      caches.keys().then(function (ks) { ks.forEach(function (k) { caches.delete(k); }); })
        .catch(function () {});
    }
  } catch (e) {}
})();
</script>
''';

/// Development server with hot reload support
class DevServer {
  final ManifestBundler manifestBundler;
  final String manifestPath;
  final String host;
  final int port;

  HttpServer? _server;
  DirectoryWatcher? _watcher;
  final List<WebSocketChannel> _clients = [];
  String _currentManifest = '{}';

  DevServer({
    required this.manifestBundler,
    required this.manifestPath,
    this.host = 'localhost',
    this.port = 3000,
  });

  /// Start the development server
  Future<void> start() async {
    // Initial bundle
    await _rebundle();

    // Start file watcher
    _startWatcher();

    // Create HTTP handler with no-cache middleware for dev
    final handler = const Pipeline()
        .addMiddleware(logRequests())
        .addMiddleware(_noCacheMiddleware())
        .addHandler(_router);

    // Start server with port-in-use handling
    try {
      _server = await shelf_io.serve(handler, host, port);
    } on SocketException catch (e) {
      if (e.osError?.errorCode == 48 ||
          e.message.contains('Address already in use')) {
        throw BundlerException(
          'Port $port is already in use.\n'
          '  → Kill the process using it: lsof -ti:$port | xargs kill\n'
          '  → Or use a different port: krom dev -p ${port + 1}',
        );
      }
      rethrow;
    }
  }

  /// Stop the development server
  Future<void> stop() async {
    await _server?.close();
    for (final client in _clients) {
      await client.sink.close();
    }
    _clients.clear();
  }

  /// No-cache middleware for dev server
  Middleware _noCacheMiddleware() {
    return (Handler handler) {
      return (Request request) async {
        final response = await handler(request);
        return response.change(headers: {
          'Cache-Control': 'no-store, no-cache, must-revalidate, max-age=0',
          'Pragma': 'no-cache',
          'Expires': '0',
        });
      };
    };
  }

  /// HTTP request router
  FutureOr<Response> _router(Request request) {
    final path = request.url.path;

    // WebSocket endpoint for hot reload
    if (path == 'ws') {
      return _handleWebSocket(request);
    }

    // Serve bundled manifest
    if (path == 'manifest.json' || path == 'bundle.json') {
      return Response.ok(
        _currentManifest,
        headers: {
          'Content-Type': 'application/json',
          'Access-Control-Allow-Origin': '*',
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
        },
      );
    }

    // Neutralise Flutter's service worker. Under the dev server's no-store
    // responses (and especially inside the VSCode webview iframe) the real SW
    // enters a cache/version reload loop that leaves the preview blank. Serve a
    // no-op SW that unregisters itself so the page renders normally.
    if (path == 'flutter_service_worker.js') {
      return Response.ok(
        _noopServiceWorkerJs,
        headers: {'Content-Type': 'application/javascript'},
      );
    }

    // Serve Flutter Web app temporarily for debugging
    if (path.isEmpty || path == 'index.html') {
      return _serveFlutterApp();
    }

    // Serve Flutter Web assets
    if (path.startsWith('flutter') ||
        path.startsWith('assets') ||
        path.endsWith('.js') ||
        path.endsWith('.wasm') ||
        path.endsWith('.json') ||
        path.endsWith('.ico')) {
      return _serveFlutterAsset(path);
    }

    return Response.notFound('Not found');
  }

  /// Handle WebSocket connections for hot reload
  FutureOr<Response> _handleWebSocket(Request request) {
    final handler = webSocketHandler((WebSocketChannel webSocket) {
      _clients.add(webSocket);
      Logger.debug('WebSocket client connected (${_clients.length} total)');

      // Send current manifest on connect
      webSocket.sink.add(_currentManifest);

      webSocket.stream.listen(
        (message) {},
        onDone: () {
          _clients.remove(webSocket);
          Logger.debug(
              'WebSocket client disconnected (${_clients.length} remaining)');
        },
        onError: (e) {
          _clients.remove(webSocket);
          Logger.debug(
              'WebSocket client error: $e (${_clients.length} remaining)');
        },
      );
    });

    return handler(request);
  }

  /// Start watching files for changes
  void _startWatcher() {
    final dir = p.dirname(p.absolute(manifestPath));
    _watcher = DirectoryWatcher(dir);

    _watcher!.events.listen((event) async {
      if (event.path.endsWith('.ks') || event.path.endsWith('manifest.json')) {
        Logger.fileChanged(p.basename(event.path));
        final timer = Logger.startTimer();
        await _rebundle();
        timer.stop();
        _notifyClients();
        Logger.debug('Rebundle took ${Logger.formatDuration(timer.elapsed)}');
      }
    });
  }

  /// Rebundle the project
  Future<void> _rebundle() async {
    try {
      _currentManifest = await manifestBundler.bundleProject(manifestPath);
      Logger.success('Manifest updated');
    } catch (e) {
      Logger.error('Bundle error: $e');
      // Keep old manifest on error
    }
  }

  /// Notify all connected clients to reload
  void _notifyClients() {
    for (final client in _clients) {
      client.sink.add(_currentManifest);
    }
    Logger.info('Notified ${_clients.length} client(s)');
  }

  /// Serve the Flutter Web preview's `index.html`.
  ///
  /// Precedence: an on-disk `web_build` (so a preview dev iterating locally with
  /// `make deploy-preview` wins), then the preview **embedded in the CLI binary**
  /// (the distributed path — works out of the box), then a "build it" page.
  Response _serveFlutterApp() {
    final webBuildDir = _resolveWebBuildDir();
    final indexPath = p.join(webBuildDir, 'index.html');
    final file = File(indexPath);

    if (file.existsSync()) {
      Logger.debug('Serving Flutter Web app from: $indexPath');
      return _htmlWithSwCleanup(file.readAsBytesSync());
    }

    final embedded = EmbeddedPreview.read('index.html');
    if (embedded != null) {
      Logger.debug(
          'Serving embedded Flutter Web preview (build ${EmbeddedPreview.buildId})');
      return _htmlWithSwCleanup(embedded);
    }

    // No on-disk build and nothing embedded (a source checkout that never ran
    // the generator): tell the user how to build/embed the preview.
    Logger.warn('Flutter web preview not built at: $indexPath');
    return Response.ok(
      _previewMissingHtml(webBuildDir),
      headers: {'Content-Type': 'text/html'},
    );
  }

  /// Serve [bytes] as `index.html` with the page-side SW-cleanup script injected
  /// right after `<head>`, so any stuck service worker is torn down on load.
  Response _htmlWithSwCleanup(List<int> bytes) {
    final html = utf8.decode(bytes, allowMalformed: true);
    final head = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(html);
    final injected = head != null
        ? html.substring(0, head.end) +
            _swCleanupHeadScript +
            html.substring(head.end)
        : _swCleanupHeadScript + html;
    return Response.ok(injected, headers: {'Content-Type': 'text/html'});
  }

  /// The mini-app project directory (where `manifest.json` lives).
  String get _projectDir => p.dirname(p.absolute(manifestPath));

  /// Serve Flutter Web assets — from an on-disk `web_build`, then the mini-app
  /// project's own assets (so relative `assets/…` references resolve in
  /// `krom dev`), then the preview embedded in the CLI binary.
  Response _serveFlutterAsset(String assetPath) {
    final webBuildDir = _resolveWebBuildDir();
    var file = File(p.join(webBuildDir, assetPath));

    // Fall back to the project's own assets (e.g. assets/images/…). web_build
    // keeps precedence so the Flutter shell's assets are never shadowed.
    if (!file.existsSync() && !assetPath.contains('..')) {
      final projectFile = File(p.join(_projectDir, assetPath));
      if (projectFile.existsSync()) file = projectFile;
    }

    if (file.existsSync()) {
      return Response.ok(
        file.readAsBytesSync(),
        headers: {'Content-Type': _contentTypeFor(assetPath)},
      );
    }

    // Distributed CLI: no on-disk web_build — serve the embedded preview file.
    final embedded = EmbeddedPreview.read(assetPath);
    if (embedded != null) {
      return Response.ok(
        embedded,
        headers: {'Content-Type': _contentTypeFor(assetPath)},
      );
    }

    return Response.notFound('Asset not found: $assetPath');
  }

  /// MIME type for a preview asset path (best-effort by extension).
  String _contentTypeFor(String path) {
    if (path.endsWith('.js')) return 'application/javascript';
    if (path.endsWith('.wasm')) return 'application/wasm';
    if (path.endsWith('.json')) return 'application/json';
    if (path.endsWith('.html')) return 'text/html';
    if (path.endsWith('.ico')) return 'image/x-icon';
    if (path.endsWith('.png')) return 'image/png';
    if (path.endsWith('.jpg') || path.endsWith('.jpeg')) return 'image/jpeg';
    if (path.endsWith('.gif')) return 'image/gif';
    if (path.endsWith('.svg')) return 'image/svg+xml';
    if (path.endsWith('.webp')) return 'image/webp';
    if (path.endsWith('.otf')) return 'font/otf';
    if (path.endsWith('.ttf')) return 'font/ttf';
    if (path.endsWith('.woff2')) return 'font/woff2';
    if (path.endsWith('.woff')) return 'font/woff';
    if (path.endsWith('.frag')) return 'text/plain';
    return 'application/octet-stream';
  }

  /// Resolve the bundled Flutter-web preview (`web_build`). Searched in
  /// order: next to the executable, the per-user install at
  /// `~/.krom/web_build` (so a globally-installed `krom` finds it from any
  /// project CWD), then `./web_build` (repo dev with `dart run`). Returns the
  /// first candidate when none exist (the caller then serves a "build the
  /// preview" page).
  String _resolveWebBuildDir() {
    final candidates = <String>[
      p.join(p.dirname(Platform.resolvedExecutable), 'web_build'),
    ];
    final home =
        Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'];
    if (home != null && home.isNotEmpty) {
      candidates.add(p.join(home, '.krom', 'web_build'));
    }
    candidates.add(p.join(Directory.current.path, 'web_build'));

    for (final c in candidates) {
      if (Directory(c).existsSync()) return c;
    }
    Logger.debug('web_build not found in: ${candidates.join(', ')}');
    return candidates.first;
  }

  /// A small page shown when the Flutter web preview has not been built yet.
  /// Mini-app rendering is handled entirely by the Flutter web app
  /// (krom_bundler_web); the dev server no longer embeds an HTML renderer.
  String _previewMissingHtml(String expectedDir) {
    return '''
<!DOCTYPE html>
<html lang="fr">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Krom Dev — aperçu non construit</title>
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
           max-width: 640px; margin: 80px auto; padding: 0 24px; color: #1c1b1f;
           line-height: 1.6; }
    h1 { font-size: 20px; }
    code { background: #f1f1f5; padding: 2px 6px; border-radius: 6px; }
    pre  { background: #f1f1f5; padding: 12px 16px; border-radius: 8px; overflow-x: auto; }
    .muted { color: #6b7280; font-size: 14px; }
  </style>
</head>
<body>
  <h1>Aperçu Flutter non construit</h1>
  <p>Le rendu de <code>krom dev</code> est assuré par l'application Flutter web
     (<code>krom_bundler_web</code>). Un <code>krom</code> distribué l'embarque et
     n'a rien à construire&nbsp;; ce message n'apparaît que sur une copie source
     où l'aperçu n'a pas encore été généré.</p>
  <p>Régénère l'aperçu embarqué (recompile le CLI), puis recharge&nbsp;:</p>
  <pre><code>cd krom_bundler_web &amp;&amp; make embed-preview</code></pre>
  <p>Ou, pour du dev local sans recompiler le CLI&nbsp;:</p>
  <pre><code>cd krom_bundler_web &amp;&amp; make deploy-preview</code></pre>
  <p class="muted">Cherché sur disque dans&nbsp;: <code>$expectedDir</code></p>
</body>
</html>
''';
  }
}
