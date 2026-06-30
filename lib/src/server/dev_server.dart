import 'dart:async';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:watcher/watcher.dart';
import 'package:path/path.dart' as p;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../bundler/bundler.dart';
import '../bundler/manifest_bundler.dart';
import '../utils/logger.dart';

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

  /// Serve Flutter Web app
  Response _serveFlutterApp() {
    final webBuildDir = _resolveWebBuildDir();
    final indexPath = p.join(webBuildDir, 'index.html');
    final file = File(indexPath);

    if (file.existsSync()) {
      Logger.debug('Serving Flutter Web app from: $indexPath');
      return Response.ok(
        file.readAsStringSync(),
        headers: {'Content-Type': 'text/html'},
      );
    }

    // Rendering is handled entirely by the Flutter web preview
    // (krom_bundler_web). The dev server no longer ships an HTML renderer, so
    // when the preview hasn't been built we just tell the user how to build it.
    Logger.warn('Flutter web preview not built at: $indexPath');
    return Response.ok(
      _previewMissingHtml(webBuildDir),
      headers: {'Content-Type': 'text/html'},
    );
  }

  /// The mini-app project directory (where `manifest.json` lives).
  String get _projectDir => p.dirname(p.absolute(manifestPath));

  /// Serve Flutter Web assets — and, as a fallback, the mini-app project's
  /// own assets so relative `assets/…` references resolve in `krom dev`.
  Response _serveFlutterAsset(String assetPath) {
    final webBuildDir = _resolveWebBuildDir();
    var file = File(p.join(webBuildDir, assetPath));

    // Fall back to the project's own assets (e.g. assets/images/…). web_build
    // keeps precedence so the Flutter shell's assets are never shadowed.
    if (!file.existsSync() && !assetPath.contains('..')) {
      final projectFile = File(p.join(_projectDir, assetPath));
      if (projectFile.existsSync()) file = projectFile;
    }

    if (!file.existsSync()) {
      return Response.notFound('Asset not found: $assetPath');
    }

    // Determine content type
    String contentType = 'application/octet-stream';
    if (assetPath.endsWith('.js')) {
      contentType = 'application/javascript';
    } else if (assetPath.endsWith('.wasm')) {
      contentType = 'application/wasm';
    } else if (assetPath.endsWith('.json')) {
      contentType = 'application/json';
    } else if (assetPath.endsWith('.ico')) {
      contentType = 'image/x-icon';
    } else if (assetPath.endsWith('.png')) {
      contentType = 'image/png';
    } else if (assetPath.endsWith('.jpg') || assetPath.endsWith('.jpeg')) {
      contentType = 'image/jpeg';
    } else if (assetPath.endsWith('.gif')) {
      contentType = 'image/gif';
    } else if (assetPath.endsWith('.svg')) {
      contentType = 'image/svg+xml';
    } else if (assetPath.endsWith('.webp')) {
      contentType = 'image/webp';
    }

    return Response.ok(
      file.readAsBytesSync(),
      headers: {'Content-Type': contentType},
    );
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
     (<code>krom_bundler_web</code>) — le serveur de dev n'embarque plus de
     moteur de rendu HTML.</p>
  <p>Construis et déploie l'aperçu, puis recharge cette page&nbsp;:</p>
  <pre><code>cd krom_bundler_web &amp;&amp; make deploy-preview</code></pre>
  <p class="muted">Attendu dans&nbsp;: <code>$expectedDir</code></p>
</body>
</html>
''';
  }
}
