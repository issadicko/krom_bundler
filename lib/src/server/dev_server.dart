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

    // Serve preview app
    if (path == 'preview') {
      return Response.ok(
        _generatePreviewHtml(),
        headers: {'Content-Type': 'text/html'},
      );
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

    Logger.debug('Flutter Web build not found at: $indexPath, using fallback');

    // Fallback to preview HTML
    return Response.ok(
      _generatePreviewHtml(),
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
  /// project CWD), then `./web_build` (repo dev with `dart run`). Falls back
  /// to the embedded lightweight HTML preview when none exist.
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

  /// Generate preview HTML page
  String _generatePreviewHtml() {
    return '''
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Krom Dev</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
      background: #111;
      color: #e0e0e0;
      height: 100vh;
      overflow: hidden;
    }

    /* Header */
    .header {
      height: 48px;
      background: #1a1a1a;
      border-bottom: 1px solid #333;
      display: flex;
      align-items: center;
      padding: 0 20px;
      gap: 16px;
    }
    .header .logo { font-size: 15px; font-weight: 700; color: #00d9ff; }
    .header .app-name { font-size: 13px; color: #888; }
    .header .spacer { flex: 1; }
    .badge {
      padding: 4px 10px;
      border-radius: 12px;
      font-size: 11px;
      font-weight: 600;
    }
    .badge.ok { background: #00c85318; color: #00c853; border: 1px solid #00c85340; }
    .badge.err { background: #ff525218; color: #ff5252; border: 1px solid #ff525240; }
    .badge.warn { background: #ff980018; color: #ff9800; border: 1px solid #ff980040; }

    /* Layout */
    .layout { display: flex; height: calc(100vh - 48px); }

    /* Sidebar */
    .sidebar {
      width: 220px;
      background: #161616;
      border-right: 1px solid #2a2a2a;
      display: flex;
      flex-direction: column;
      overflow-y: auto;
    }
    .sidebar-section { padding: 16px 14px 8px; }
    .sidebar-title {
      font-size: 10px;
      font-weight: 700;
      color: #666;
      text-transform: uppercase;
      letter-spacing: 1px;
      margin-bottom: 8px;
    }
    .nav-item {
      padding: 8px 12px;
      border-radius: 6px;
      cursor: pointer;
      font-size: 13px;
      color: #aaa;
      transition: all 0.15s;
      display: flex;
      align-items: center;
      gap: 8px;
    }
    .nav-item:hover { background: #222; color: #e0e0e0; }
    .nav-item.active { background: #00d9ff15; color: #00d9ff; }
    .nav-icon { font-size: 14px; }

    /* Main area */
    .main {
      flex: 1;
      display: flex;
      align-items: center;
      justify-content: center;
      background: #0e0e0e;
      padding: 24px;
    }

    /* Phone frame */
    .phone {
      width: 380px;
      height: 760px;
      background: #000;
      border-radius: 40px;
      padding: 12px;
      box-shadow: 0 20px 60px rgba(0,0,0,0.5);
      position: relative;
    }
    .phone-screen {
      width: 100%;
      height: 100%;
      background: #fff;
      border-radius: 30px;
      overflow: hidden;
      display: flex;
      flex-direction: column;
    }
    .phone-notch {
      height: 34px;
      background: #f8f8f8;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 13px;
      font-weight: 600;
      color: #333;
    }
    .phone-content {
      flex: 1;
      overflow-y: auto;
      padding: 0;
    }

    /* Right panel */
    .panel {
      width: 340px;
      background: #161616;
      border-left: 1px solid #2a2a2a;
      display: flex;
      flex-direction: column;
    }
    .panel-tabs {
      display: flex;
      border-bottom: 1px solid #2a2a2a;
    }
    .panel-tab {
      flex: 1;
      padding: 10px;
      text-align: center;
      font-size: 12px;
      font-weight: 600;
      color: #666;
      cursor: pointer;
      border-bottom: 2px solid transparent;
      transition: all 0.15s;
    }
    .panel-tab:hover { color: #aaa; }
    .panel-tab.active { color: #00d9ff; border-bottom-color: #00d9ff; }
    .panel-content {
      flex: 1;
      overflow: auto;
      padding: 12px;
    }
    pre.code {
      background: #0e0e0e;
      color: #c8d6e5;
      padding: 14px;
      border-radius: 8px;
      font-size: 12px;
      line-height: 1.6;
      overflow-x: auto;
      white-space: pre-wrap;
      word-break: break-word;
      font-family: 'SF Mono', 'Fira Code', 'Consolas', monospace;
    }
    .info-grid {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 8px;
    }
    .info-card {
      background: #0e0e0e;
      border-radius: 8px;
      padding: 12px;
    }
    .info-card .label { font-size: 10px; color: #666; text-transform: uppercase; letter-spacing: 0.5px; }
    .info-card .value { font-size: 16px; font-weight: 700; margin-top: 4px; color: #e0e0e0; }

    /* KromScript UI rendering */
    .ks-box { border-radius: 0; }
    .ks-text { font-family: -apple-system, sans-serif; }
    .ks-column { display: flex; flex-direction: column; }
    .ks-row { display: flex; flex-direction: row; }
    .ks-center { align-items: center; justify-content: center; }
    .ks-inkwell { cursor: pointer; transition: opacity 0.15s; }
    .ks-inkwell:hover { opacity: 0.85; }
    .ks-inkwell:active { opacity: 0.7; }
  </style>
</head>
<body>
  <div class="header">
    <span class="logo">Krom</span>
    <span class="app-name" id="app-name">Loading...</span>
    <div class="spacer"></div>
    <div class="badge" id="status">Connecting...</div>
  </div>

  <div class="layout">
    <div class="sidebar">
      <div class="sidebar-section">
        <div class="sidebar-title">Pages</div>
        <div id="pages-nav"></div>
      </div>
      <div class="sidebar-section">
        <div class="sidebar-title">Components</div>
        <div id="components-nav"></div>
      </div>
    </div>

    <div class="main">
      <div class="phone">
        <div class="phone-screen">
          <div class="phone-notch">9:41</div>
          <div class="phone-content" id="phone-content">
            <div style="display:flex;align-items:center;justify-content:center;height:100%;color:#aaa;font-size:14px;">
              Connecting...
            </div>
          </div>
        </div>
      </div>
    </div>

    <div class="panel">
      <div class="panel-tabs">
        <div class="panel-tab active" data-tab="code" onclick="switchTab('code')">Code</div>
        <div class="panel-tab" data-tab="info" onclick="switchTab('info')">Info</div>
      </div>
      <div class="panel-content" id="panel-body">
        <pre class="code" id="code-output">Waiting for manifest...</pre>
      </div>
    </div>
  </div>

  <script>
    let manifest = {};
    let currentView = null;
    let currentTab = 'code';
    let ws;

    function connect() {
      ws = new WebSocket('ws://$host:$port/ws');

      ws.onopen = () => {
        const s = document.getElementById('status');
        s.textContent = 'Live';
        s.className = 'badge ok';
      };

      ws.onclose = () => {
        const s = document.getElementById('status');
        s.textContent = 'Disconnected';
        s.className = 'badge err';
        setTimeout(connect, 2000);
      };

      ws.onerror = () => {};

      ws.onmessage = (e) => {
        try {
          manifest = JSON.parse(e.data);
          document.getElementById('app-name').textContent =
            (manifest.name || 'App') + ' v' + (manifest.version || '?');
          updateNav();
          if (!currentView && manifest.entry) {
            selectPage(manifest.entry);
          } else if (currentView) {
            refreshCurrentView();
          }
        } catch (err) {
          console.error('Parse error:', err);
        }
      };
    }

    function updateNav() {
      const pn = document.getElementById('pages-nav');
      const cn = document.getElementById('components-nav');
      pn.innerHTML = '';
      cn.innerHTML = '';

      if (manifest.pages) {
        for (const [id, page] of Object.entries(manifest.pages)) {
          const d = document.createElement('div');
          d.className = 'nav-item' + (currentView === 'page:' + id ? ' active' : '');
          d.innerHTML = '<span class="nav-icon">' + iconFor(page.icon) + '</span>' + (page.name || id);
          d.onclick = () => selectPage(id);
          pn.appendChild(d);
        }
      }

      if (manifest.components) {
        for (const [id, comp] of Object.entries(manifest.components)) {
          const d = document.createElement('div');
          d.className = 'nav-item' + (currentView === 'comp:' + id ? ' active' : '');
          d.innerHTML = '<span class="nav-icon">&#9638;</span>' + (comp.name || id);
          d.onclick = () => selectComponent(id);
          cn.appendChild(d);
        }
      }
    }

    function iconFor(name) {
      const icons = { home: '&#9751;', settings: '&#9881;', person: '&#9787;', search: '&#128269;', add: '&#43;', list: '&#9776;' };
      return icons[name] || '&#9679;';
    }

    function selectPage(id) {
      currentView = 'page:' + id;
      const page = manifest.pages?.[id];
      if (page) {
        renderScript(page.script);
        updatePanel(page.script, page.name || id);
      }
      updateNav();
    }

    function selectComponent(id) {
      currentView = 'comp:' + id;
      const comp = manifest.components?.[id];
      if (comp) {
        renderScript(comp.script);
        updatePanel(comp.script, comp.name || id);
      }
      updateNav();
    }

    function refreshCurrentView() {
      if (currentView?.startsWith('page:')) selectPage(currentView.slice(5));
      else if (currentView?.startsWith('comp:')) selectComponent(currentView.slice(5));
    }

    function switchTab(tab) {
      currentTab = tab;
      document.querySelectorAll('.panel-tab').forEach(t => {
        t.classList.toggle('active', t.dataset.tab === tab);
      });
      refreshCurrentView();
    }

    function updatePanel(script, name) {
      const body = document.getElementById('panel-body');
      if (currentTab === 'code') {
        body.innerHTML = '<pre class="code">' + escapeHtml(script || '') + '</pre>';
      } else {
        const pages = Object.keys(manifest.pages || {}).length;
        const comps = Object.keys(manifest.components || {}).length;
        const size = new Blob([JSON.stringify(manifest)]).size;
        body.innerHTML = '<div class="info-grid">' +
          infoCard('App', manifest.name || '?') +
          infoCard('Version', manifest.version || '?') +
          infoCard('Pages', pages) +
          infoCard('Components', comps) +
          infoCard('Entry', manifest.entry || '?') +
          infoCard('Size', formatSize(size)) +
          '</div>';
      }
    }

    function infoCard(label, value) {
      return '<div class="info-card"><div class="label">' + label + '</div><div class="value">' + value + '</div></div>';
    }

    function formatSize(bytes) {
      if (bytes < 1024) return bytes + ' B';
      return (bytes / 1024).toFixed(1) + ' KB';
    }

    function escapeHtml(s) {
      s = String(s == null ? '' : s);
      return s.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    }

    // ── KromScript UI renderer ──
    function renderScript(script) {
      const phone = document.getElementById('phone-content');
      try {
        const buildMatch = script.match(/fn\\s+build\\s*\\(\\)\\s*\\{[\\s\\S]*?return\\s+([\\s\\S]*?)\\n\\}/);
        if (buildMatch) {
          const tree = parseWidget(buildMatch[1].trim());
          phone.innerHTML = renderWidget(tree);
        } else {
          phone.innerHTML = '<div style="padding:24px;color:#888;font-size:13px;">No build() function found</div>';
        }
      } catch (e) {
        phone.innerHTML = '<div style="padding:24px;color:#888;font-size:13px;">Preview unavailable</div>';
        console.error('Render error:', e);
      }
    }

    // Return the content between the first balanced parentheses of `src`
    // (which must start at the opening '('), respecting strings/nesting.
    function innerParens(src) {
      let depth = 0, out = '', inStr = false, strCh = '';
      for (let i = 0; i < src.length; i++) {
        const ch = src[i];
        if ((ch === '"' || ch === "'") && (i === 0 || src[i-1] !== '\\\\')) {
          if (!inStr) { inStr = true; strCh = ch; } else if (ch === strCh) inStr = false;
        }
        if (!inStr) {
          if (ch === '(') { depth++; if (depth === 1) continue; }
          else if (ch === ')') { depth--; if (depth === 0) return out; }
        }
        if (depth >= 1) out += ch;
      }
      return out;
    }

    // Parse a { key: value, ... } object literal. Widget-valued and
    // array-valued props are parsed recursively (e.g. Scaffold appBar).
    function parseProps(objStr) {
      const inner = objStr.replace(/^\\{/, '').replace(/\\}\$/, '');
      const props = {};
      splitTopLevel(inner).forEach(pair => {
        const idx = pair.indexOf(':');
        if (idx <= 0) return;
        const k = pair.slice(0, idx).trim().replace(/^["']|["']\$/g, '');
        const v = pair.slice(idx + 1).trim();
        if (/^[A-Z]\\w*\\s*\\(/.test(v)) props[k] = parseWidget(v);
        else if (v[0] === '[') props[k] = splitTopLevel(v.slice(1, -1)).map(parseWidget).filter(Boolean);
        else props[k] = v.replace(/^["']|["']\$/g, '');
      });
      return props;
    }

    function parseWidget(src) {
      src = src.trim();
      const nameMatch = src.match(/^([A-Z]\\w*)\\s*\\(/);
      if (!nameMatch) return { type: 'raw', text: src };
      const name = nameMatch[1];
      // Classify each top-level argument: props object, children array,
      // a positional child widget (Scaffold/Card/Box/...), or a literal.
      const inner = innerParens(src.slice(nameMatch[0].length - 1));
      let props = {}, args = [], children = [];
      splitTopLevel(inner).forEach(part => {
        const t = part.trim();
        if (!t) return;
        if (t[0] === '{') props = parseProps(t);
        else if (t[0] === '[') children = children.concat(splitTopLevel(t.slice(1, -1)).map(parseWidget).filter(Boolean));
        else if (/^[A-Z]\\w*\\s*\\(/.test(t)) children.push(parseWidget(t));
        else args.push(t.replace(/^["']|["']\$/g, ''));
      });
      return { type: name, props, args, children };
    }

    function splitTopLevel(src) {
      const parts = [];
      let depth = 0;
      let current = '';
      let inStr = false;
      let strCh = '';

      for (let i = 0; i < src.length; i++) {
        const ch = src[i];
        if ((ch === '"' || ch === "'") && (i === 0 || src[i-1] !== '\\\\')) {
          if (!inStr) { inStr = true; strCh = ch; }
          else if (ch === strCh) inStr = false;
        }
        if (!inStr) {
          if (ch === '(' || ch === '[' || ch === '{') depth++;
          if (ch === ')' || ch === ']' || ch === '}') depth--;
          if (ch === ',' && depth === 0) {
            if (current.trim()) parts.push(current.trim());
            current = '';
            continue;
          }
        }
        current += ch;
      }
      if (current.trim()) parts.push(current.trim());
      return parts;
    }

    function renderWidget(w) {
      if (!w) return '';
      if (w.type === 'raw') return '<span>' + escapeHtml(w.text) + '</span>';

      const p = w.props || {};
      const ch = (w.children || []).map(renderWidget).join('');
      // A single positional child (Scaffold/Box/Card/...) lands in children;
      // an explicit `body:` prop wins when present.
      const body = p.body ? renderWidget(p.body) : ch;
      const a0 = (w.args && w.args[0]) || '';

      switch (w.type) {
        case 'Scaffold':
          return '<div style="' + (p.backgroundColor ? 'background:' + p.backgroundColor + ';' : '') + 'min-height:100%;display:flex;flex-direction:column;">' +
            (p.appBar ? renderWidget(p.appBar) : '') +
            '<div style="flex:1;">' + body + '</div></div>';

        case 'AppBar':
          return '<div style="background:' + (p.backgroundColor || '#6200ee') + ';color:#fff;padding:14px 16px;font-weight:600;font-size:15px;">' +
            escapeHtml(p.title || a0) + '</div>';

        case 'Card':
          return '<div style="' +
            (p.color ? 'background:' + p.color + ';' : 'background:#fff;') +
            (p.padding ? 'padding:' + p.padding + 'px;' : 'padding:12px;') +
            (p.borderRadius ? 'border-radius:' + p.borderRadius + 'px;' : 'border-radius:8px;') +
            'box-shadow:0 1px 4px rgba(0,0,0,0.12);">' + body + '</div>';

        case 'Box':
        case 'Container':
        case 'Padding':
          return '<div style="' +
            (p.color ? 'background:' + p.color + ';' : '') +
            (p.padding ? 'padding:' + p.padding + 'px;' : '') +
            (p.borderRadius ? 'border-radius:' + p.borderRadius + 'px;' : '') +
            (p.width === 'infinity' ? 'width:100%;box-sizing:border-box;' : (p.width ? 'width:' + p.width + 'px;' : '')) +
            (p.height === 'infinity' ? 'min-height:100%;' : (p.height ? 'height:' + p.height + 'px;' : '')) +
            '">' + body + '</div>';

        case 'Column':
          return '<div style="display:flex;flex-direction:column;' +
            (p.spacing ? 'gap:' + p.spacing + 'px;' : '') +
            (p.crossAxisAlignment === 'center' ? 'align-items:center;' : '') +
            (p.mainAxisAlignment === 'center' ? 'justify-content:center;' : '') +
            '">' + ch + '</div>';

        case 'Row':
          return '<div style="display:flex;flex-direction:row;' +
            (p.spacing ? 'gap:' + p.spacing + 'px;' : '') +
            (p.crossAxisAlignment === 'center' ? 'align-items:center;' : '') +
            (p.mainAxisAlignment === 'center' ? 'justify-content:center;' : '') +
            '">' + ch + '</div>';

        case 'Center':
          return '<div style="display:flex;align-items:center;justify-content:center;">' + body + '</div>';

        case 'Expanded':
        case 'ScrollView':
        case 'ListView':
        case 'SizedBox':
        case 'InkWell':
          return '<div style="' + (w.type === 'Expanded' ? 'flex:1;' : '') +
            (p.borderRadius ? 'border-radius:' + p.borderRadius + 'px;' : '') + '">' + body + '</div>';

        case 'Text':
          return '<span style="' +
            (p.fontSize ? 'font-size:' + p.fontSize + 'px;' : '') +
            (p.fontWeight ? 'font-weight:' + p.fontWeight + ';' : '') +
            (p.color ? 'color:' + p.color + ';' : '') +
            '">' + escapeHtml(a0 || p.content || '') + '</span>';

        case 'TextField':
        case 'Input':
          return '<div style="display:flex;flex-direction:column;gap:4px;margin:4px 0;">' +
            (p.labelText ? '<label style="font-size:12px;color:#555;">' + escapeHtml(p.labelText) + '</label>' : '') +
            '<input placeholder="' + escapeHtml(p.placeholder || p.labelText || '') + '" style="padding:8px;border:1px solid #ccc;border-radius:6px;font-size:13px;"/></div>';

        case 'Button':
          return '<button style="' +
            (p.color ? 'background:' + p.color + ';color:#fff;' : 'background:#6200ee;color:#fff;') +
            'border:none;padding:10px 16px;border-radius:8px;font-size:14px;cursor:pointer;margin:4px 0;">' +
            escapeHtml(a0 || p.label || 'Button') + '</button>';

        case 'Icon':
          return '<span title="' + escapeHtml(a0 || p.name || '') + '" style="font-size:' + (p.size || 20) + 'px;color:' + (p.color || '#666') + ';">[icon]</span>';

        case 'Image':
          return '<div style="background:#eee;border-radius:6px;min-height:60px;display:flex;align-items:center;justify-content:center;color:#999;font-size:11px;">image</div>';

        case 'Divider':
          return '<hr style="border:none;border-top:1px solid #e0e0e0;margin:8px 0;"/>';

        case 'Obx':
          return '<div style="padding:4px;color:#aaa;font-size:12px;font-style:italic;">[Reactive: ' + (p.builder || '?') + ']</div>';

        case 'TabNav': {
          // Top tabs. The tab items are object literals (parsed as raw); pull
          // their label/builder with a regex. The active tab's content comes
          // from a builder we can't invoke here, so show a reactive placeholder.
          const tabs = Array.isArray(p.tabs) ? p.tabs : [];
          const chips = tabs.map(function (t, i) {
            const raw = (t && t.text) || '';
            const m = raw.match(/label:\\s*"([^"]*)"/);
            const label = m ? m[1] : 'Onglet';
            return '<span style="padding:8px 12px;font-size:13px;' +
              (i === 0
                ? 'color:#2563EB;border-bottom:2px solid #2563EB;font-weight:600;'
                : 'color:#888;border-bottom:2px solid transparent;') +
              '">' + escapeHtml(label) + '</span>';
          }).join('');
          const firstRaw = (tabs[0] && tabs[0].text) || '';
          const bm = firstRaw.match(/builder:\\s*"([^"]*)"/);
          return '<div style="display:flex;border-bottom:1px solid #eee;' +
            (p.backgroundColor ? 'background:' + p.backgroundColor + ';' : '') +
            '">' + chips + '</div>' +
            '<div style="padding:8px;color:#aaa;font-size:12px;font-style:italic;">[Reactive: ' +
            escapeHtml(bm ? bm[1] : '?') + ']</div>';
        }

        case 'ListTile':
          return '<div style="display:flex;align-items:center;gap:12px;padding:8px 4px;">' +
            (p.leading ? renderWidget(p.leading) : '') +
            '<div style="flex:1;">' + (p.title ? renderWidget(p.title) : '') + (p.subtitle ? renderWidget(p.subtitle) : '') + '</div>' +
            (p.trailing ? renderWidget(p.trailing) : '') + '</div>';

        default:
          return '<div style="padding:4px;border:1px dashed #ddd;border-radius:4px;margin:2px;font-size:11px;color:#888;">' +
            w.type + (ch ? '<div style="padding-left:8px;">' + ch + '</div>' : '') + '</div>';
      }
    }

    connect();
  </script>
</body>
</html>
''';
  }
}
