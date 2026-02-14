import 'dart:async';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_web_socket/shelf_web_socket.dart';
import 'package:watcher/watcher.dart';
import 'package:path/path.dart' as p;
import 'package:web_socket_channel/web_socket_channel.dart';
import '../bundler/manifest_bundler.dart';

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

    // Create HTTP handler
    final handler =
        const Pipeline().addMiddleware(logRequests()).addHandler(_router);

    // Start server
    _server = await shelf_io.serve(handler, host, port);
  }

  /// Stop the development server
  Future<void> stop() async {
    await _server?.close();
    for (final client in _clients) {
      await client.sink.close();
    }
    _clients.clear();
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

    // Serve Flutter Web app
    if (path.isEmpty || path == 'index.html' || path == 'app') {
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

    // Fallback to old preview HTML for compatibility
    if (path == 'preview') {
      return Response.ok(
        _generatePreviewHtml(),
        headers: {'Content-Type': 'text/html'},
      );
    }

    return Response.notFound('Not found');
  }

  /// Handle WebSocket connections for hot reload
  FutureOr<Response> _handleWebSocket(Request request) {
    final handler = webSocketHandler((WebSocketChannel webSocket) {
      _clients.add(webSocket);

      // Send current manifest on connect
      webSocket.sink.add(_currentManifest);

      webSocket.stream.listen(
        (message) {},
        onDone: () {
          _clients.remove(webSocket);
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
        print('📝 Changed: ${p.basename(event.path)}');
        await _rebundle();
        _notifyClients();
      }
    });
  }

  /// Rebundle the project
  Future<void> _rebundle() async {
    try {
      _currentManifest = await manifestBundler.bundleProject(manifestPath);
      print('📦 Manifest updated');
    } catch (e) {
      print('❌ Bundle error: $e');
      // Keep old manifest on error
    }
  }

  /// Notify all connected clients to reload
  void _notifyClients() {
    for (final client in _clients) {
      client.sink.add(_currentManifest);
    }
    print('🔄 Notified ${_clients.length} clients');
  }

  /// Serve Flutter Web app
  Response _serveFlutterApp() {
    // Path to the built Flutter web app (check web_build directory)
    final webBuildDir =
        p.join(p.dirname(p.dirname(p.absolute(manifestPath))), 'web_build');
    final indexPath = p.join(webBuildDir, 'index.html');
    final file = File(indexPath);

    if (file.existsSync()) {
      print('📱 Serving Flutter Web app from: $indexPath');
      return Response.ok(
        file.readAsStringSync(),
        headers: {'Content-Type': 'text/html'},
      );
    }

    print('⚠️  Flutter Web build not found at: $indexPath');
    print('   Using fallback HTML preview');

    // Fallback to inline Flutter web app
    return Response.ok(
      _generateFlutterWebHtml(),
      headers: {'Content-Type': 'text/html'},
    );
  }

  /// Serve Flutter Web assets
  Response _serveFlutterAsset(String assetPath) {
    final webBuildDir =
        p.join(p.dirname(p.dirname(p.absolute(manifestPath))), 'web_build');
    final file = File(p.join(webBuildDir, assetPath));

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
    }

    return Response.ok(
      file.readAsBytesSync(),
      headers: {'Content-Type': contentType},
    );
  }

  /// Generate inline Flutter Web HTML
  String _generateFlutterWebHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Krom Bundler Web Preview</title>
  <style>
    body { margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif; }
    .container { display: flex; height: 100vh; }
    .sidebar { width: 300px; background: #f5f5f5; padding: 20px; box-sizing: border-box; overflow-y: auto; }
    .preview { flex: 1; background: white; position: relative; }
    .phone-frame { 
      width: 375px; height: 667px; margin: 20px auto; 
      border: 8px solid #333; border-radius: 25px; 
      background: white; position: relative; overflow: hidden;
    }
    .status-bar { height: 20px; background: #000; color: white; font-size: 12px; text-align: center; line-height: 20px; }
    .app-content { height: calc(100% - 20px); overflow: hidden; }
    .loading { display: flex; align-items: center; justify-content: center; height: 100%; }
    .error { color: red; padding: 20px; }
    .connected { color: green; }
    .disconnected { color: red; }
  </style>
</head>
<body>
  <div class="container">
    <div class="sidebar">
      <h2>Krom Bundler</h2>
      <div id="status" class="disconnected">Connecting...</div>
      <div id="app-info"></div>
    </div>
    <div class="preview">
      <div class="phone-frame">
        <div class="status-bar">9:41 AM</div>
        <div class="app-content">
          <div id="app-container" class="loading">
            <div>Loading KromScript app...</div>
          </div>
        </div>
      </div>
    </div>
  </div>

  <script>
    let ws;
    let currentManifest = null;

    function connect() {
      ws = new WebSocket('ws://localhost:3000/ws');
      
      ws.onopen = function() {
        document.getElementById('status').textContent = 'Connected - Live Reload Active';
        document.getElementById('status').className = 'connected';
      };
      
      ws.onmessage = function(event) {
        try {
          currentManifest = JSON.parse(event.data);
          updateUI();
        } catch (e) {
          console.error('Invalid manifest:', e);
        }
      };
      
      ws.onclose = function() {
        document.getElementById('status').textContent = 'Disconnected';
        document.getElementById('status').className = 'disconnected';
        setTimeout(connect, 2000); // Reconnect after 2 seconds
      };
      
      ws.onerror = function(error) {
        console.error('WebSocket error:', error);
      };
    }

    function updateUI() {
      if (!currentManifest) return;
      
      // Update app info
      const appInfo = document.getElementById('app-info');
      appInfo.innerHTML = `
        <h3>\${currentManifest.name || 'Unknown App'}</h3>
        <p>Version: \${currentManifest.version || 'Unknown'}</p>
        <p>Pages: \${Object.keys(currentManifest.pages || {}).length}</p>
      `;
      
      // Update app preview
      const container = document.getElementById('app-container');
      container.innerHTML = `
        <div style="padding: 20px; text-align: center;">
          <h2>\${currentManifest.name}</h2>
          <p>KromScript Mini-App Preview</p>
          <p style="font-size: 12px; color: #666;">
            This is a simplified preview. The full Flutter Web version 
            will render the actual KromScript UI components.
          </p>
        </div>
      `;
    }

    // Start connection
    connect();
  </script>
</body>
</html>
    ''';
  }

  /// Generate preview HTML page
  String _generatePreviewHtml() {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Krom Mini-App Preview</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #0f0f23;
      color: #e0e0e0;
      min-height: 100vh;
    }
    .header {
      background: #1a1a2e;
      padding: 16px 24px;
      border-bottom: 1px solid #333;
      display: flex;
      justify-content: space-between;
      align-items: center;
    }
    .header h1 { font-size: 18px; color: #00d9ff; }
    .status { 
      padding: 6px 12px;
      border-radius: 16px;
      font-size: 12px;
      font-weight: 500;
    }
    .connected { background: #00c85320; color: #00c853; border: 1px solid #00c853; }
    .disconnected { background: #ff525220; color: #ff5252; border: 1px solid #ff5252; }
    .container { display: flex; height: calc(100vh - 60px); }
    .sidebar {
      width: 240px;
      background: #1a1a2e;
      border-right: 1px solid #333;
      padding: 16px;
    }
    .sidebar h3 { font-size: 12px; color: #888; margin-bottom: 12px; text-transform: uppercase; }
    .nav-item {
      padding: 10px 12px;
      border-radius: 8px;
      cursor: pointer;
      margin-bottom: 4px;
      transition: background 0.2s;
    }
    .nav-item:hover { background: #333; }
    .nav-item.active { background: #00d9ff20; color: #00d9ff; }
    .preview {
      flex: 1;
      padding: 24px;
      overflow: auto;
    }
    .preview-frame {
      background: #1a1a2e;
      border-radius: 12px;
      padding: 20px;
      max-width: 400px;
      margin: 0 auto;
      min-height: 600px;
    }
    pre {
      background: #16213e;
      padding: 16px;
      border-radius: 8px;
      overflow-x: auto;
      font-size: 12px;
      line-height: 1.5;
    }
  </style>
</head>
<body>
  <div class="header">
    <h1>🚀 Krom Mini-App Preview</h1>
    <div id="status" class="status disconnected">Disconnected</div>
  </div>
  
  <div class="container">
    <div class="sidebar">
      <h3>Pages</h3>
      <div id="pages-nav"></div>
      <h3 style="margin-top: 20px;">Components</h3>
      <div id="components-nav"></div>
    </div>
    
    <div class="preview">
      <div class="preview-frame">
        <pre id="output">Connecting...</pre>
      </div>
    </div>
  </div>

  <script>
    let manifest = {};
    let currentView = null;
    
    const ws = new WebSocket('ws://$host:$port/ws');
    const status = document.getElementById('status');
    const output = document.getElementById('output');
    const pagesNav = document.getElementById('pages-nav');
    const componentsNav = document.getElementById('components-nav');

    ws.onopen = () => {
      status.textContent = 'Connected';
      status.className = 'status connected';
    };

    ws.onclose = () => {
      status.textContent = 'Disconnected';
      status.className = 'status disconnected';
    };

    ws.onmessage = (e) => {
      try {
        manifest = JSON.parse(e.data);
        updateNav();
        if (!currentView && manifest.entry) {
          selectPage(manifest.entry);
        } else if (currentView) {
          refreshCurrentView();
        }
      } catch (err) {
        output.textContent = 'Error: ' + err;
      }
    };

    function updateNav() {
      pagesNav.innerHTML = '';
      componentsNav.innerHTML = '';
      
      if (manifest.pages) {
        for (const [id, page] of Object.entries(manifest.pages)) {
          const div = document.createElement('div');
          div.className = 'nav-item' + (currentView === 'page:' + id ? ' active' : '');
          div.textContent = page.name || id;
          div.onclick = () => selectPage(id);
          pagesNav.appendChild(div);
        }
      }
      
      if (manifest.components) {
        for (const [id, comp] of Object.entries(manifest.components)) {
          const div = document.createElement('div');
          div.className = 'nav-item' + (currentView === 'component:' + id ? ' active' : '');
          div.textContent = comp.name || id;
          div.onclick = () => selectComponent(id);
          componentsNav.appendChild(div);
        }
      }
    }

    function selectPage(id) {
      currentView = 'page:' + id;
      const page = manifest.pages?.[id];
      output.textContent = page?.script || 'Page not found';
      updateNav();
    }

    function selectComponent(id) {
      currentView = 'component:' + id;
      const comp = manifest.components?.[id];
      output.textContent = comp?.script || 'Component not found';
      updateNav();
    }

    function refreshCurrentView() {
      if (currentView?.startsWith('page:')) {
        selectPage(currentView.slice(5));
      } else if (currentView?.startsWith('component:')) {
        selectComponent(currentView.slice(10));
      }
    }
  </script>
</body>
</html>
''';
  }
}
