import 'dart:async';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import 'package:watcher/watcher.dart';
import '../backend/backend_client.dart';
import '../backend/project_ref.dart';
import '../server/dev_server.dart';
import '../bundler/bundler.dart';
import '../bundler/manifest_bundler.dart';
import '../utils/config.dart';
import '../utils/logger.dart';
import '../utils/terminal_qr.dart';

/// Dev command - starts development server with hot reload
class DevCommand extends Command<int> {
  @override
  final name = 'dev';

  @override
  final description = 'Start development server with hot reload';

  DevCommand() {
    argParser
      ..addOption(
        'manifest',
        abbr: 'm',
        help: 'Path to manifest.json',
        defaultsTo: 'manifest.json',
      )
      ..addOption(
        'port',
        abbr: 'p',
        help: 'Server port',
        defaultsTo: '3000',
      )
      ..addOption(
        'host',
        help: 'Server host. Defaults to 0.0.0.0 so a phone on the same '
            'network can scan-to-test (use "localhost" to stay local-only).',
        defaultsTo: '0.0.0.0',
      )
      ..addFlag(
        'qr',
        help: 'Print a scan-to-test QR code (Krom Go) at startup.',
        defaultsTo: true,
      )
      ..addFlag(
        'remote',
        help: 'Test on a real device OR emulator through the backend: opens a '
            'dev channel, prints a short code to type in the host app, and '
            'pushes each rebuild live (no scan, no publish). Requires login.',
        defaultsTo: false,
      );
  }

  @override
  Future<int> run() async {
    final manifestPath = argResults!['manifest'] as String;
    final portStr = argResults!['port'] as String;
    final host = argResults!['host'] as String;

    // Validate port
    final port = int.tryParse(portStr);
    if (port == null || port < 1 || port > 65535) {
      Logger.bundleError(
        message: 'Invalid port: $portStr',
        suggestion: 'Port must be a number between 1 and 65535.',
      );
      return 1;
    }

    // Validate manifest exists
    if (!File(manifestPath).existsSync()) {
      Logger.bundleError(
        message: 'Manifest not found: $manifestPath',
        suggestion:
            'Run "krom init <name>" to create a new project, or use --manifest to specify the path.',
      );
      return 1;
    }

    if (argResults!['remote'] as bool) {
      return _runRemote(manifestPath);
    }

    try {
      final bundler = ManifestBundler();
      final server = DevServer(
        manifestBundler: bundler,
        manifestPath: manifestPath,
        host: host,
        port: port,
      );

      await server.start();

      Logger.serverStarted(
        host: host,
        port: port,
        manifestPath: manifestPath,
      );

      await _printScanTarget(host, port);

      // Keep running until interrupted
      await ProcessSignal.sigint.watch().first;

      Logger.newline();
      Logger.info('Shutting down...');
      await server.stop();
      Logger.success('Server stopped.');

      return 0;
    } on BundlerException catch (e) {
      Logger.bundleError(
        message: e.message,
        suggestion: 'Fix the error above and restart with "krom dev".',
      );
      return 1;
    } catch (e) {
      Logger.error('Dev server failed: $e');
      return 1;
    }
  }

  /// Prints the LAN scan target (URL + QR) for the Krom Go host app. Skipped
  /// with --no-qr, when bound local-only, or when no LAN address exists.
  Future<void> _printScanTarget(String host, int port) async {
    if (!(argResults!['qr'] as bool)) return;
    if (host == 'localhost' || host == '127.0.0.1') {
      Logger.hint('Bound to $host — no scan-to-test '
          '(default --host 0.0.0.0 exposes the LAN QR).');
      return;
    }
    final lan = await lanIPv4();
    if (lan == null) {
      Logger.hint('No LAN address found — connect to a network to scan-to-test.');
      return;
    }
    final url = 'http://$lan:$port';
    final qr = terminalQr(url);
    if (qr.isEmpty) return;
    Logger.newline();
    Logger.info('Scan to test on your device (Krom Go):');
    Logger.keyValue('URL', url);
    Logger.newline();
    stdout.write(qr);
    Logger.newline();
  }

  /// `krom dev --remote`: test live on a device OR emulator through the backend.
  /// Opens an ephemeral dev channel, prints a short code to type in the host app
  /// (no scan, no publish), then pushes the freshly bundled manifest on every
  /// save so the device hot-reloads.
  Future<int> _runRemote(String manifestPath) async {
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

    final ManifestRef manifest;
    try {
      manifest = ManifestRef.load(manifestPath);
    } catch (e) {
      Logger.error('Invalid manifest.json: $e');
      return 1;
    }
    if (manifest.slug == null) {
      Logger.error('manifest.json must have an "id" (used as the app slug).');
      return 1;
    }

    final client = BackendClient(baseUrl: remoteUrl, token: token);
    final bundler = ManifestBundler();
    StreamSubscription<WatchEvent>? sub;
    try {
      Logger.step(1, 2, 'Resolving app "${manifest.slug}"...');
      final app = (await resolveProjectApp(client: client, manifest: manifest))!;
      Logger.keyValue('App', '${app.name} (${app.id})');

      Logger.step(2, 2, 'Opening dev channel...');
      final channel = await client.openDevChannel(app.id);

      // First bundle + push. Keep the session alive on a bundle error so it can
      // be fixed live (the device shows the error overlay meanwhile).
      await _bundleAndPush(bundler, client, manifestPath, channel.code);

      _printRemoteTarget(remoteUrl, channel);

      final dir = p.dirname(p.absolute(manifestPath));
      sub = DirectoryWatcher(dir).events.listen((event) async {
        if (event.path.endsWith('.ks') ||
            event.path.endsWith('manifest.json')) {
          Logger.fileChanged(p.basename(event.path));
          await _bundleAndPush(bundler, client, manifestPath, channel.code);
        }
      });

      Logger.newline();
      Logger.info('Watching for changes — save to hot-reload the device. '
          'Ctrl-C to stop.');
      await ProcessSignal.sigint.watch().first;

      Logger.newline();
      Logger.info('Stopped.');
      return 0;
    } on BackendException catch (e) {
      Logger.error(
          e.message + (e.statusCode != null ? ' (${e.statusCode})' : ''));
      if (e.body != null && e.body!.isNotEmpty) Logger.debug(e.body!);
      return 1;
    } catch (e) {
      Logger.error('Remote dev failed: $e');
      return 1;
    } finally {
      await sub?.cancel();
      client.close();
    }
  }

  /// Bundles the project and pushes it to the dev channel. On a bundle error,
  /// surfaces it on the device as an overlay and keeps the session alive.
  Future<bool> _bundleAndPush(ManifestBundler bundler, BackendClient client,
      String manifestPath, String code) async {
    final timer = Logger.startTimer();
    try {
      final compiled = await bundler.bundleProjectToMap(manifestPath);
      final version = await client.pushDevBundle(code: code, manifest: compiled);
      timer.stop();
      Logger.success('Pushed v$version '
          '(${Logger.formatDuration(timer.elapsed)}) — device reloading.');
      return true;
    } on BundlerException catch (e) {
      timer.stop();
      Logger.error('Bundle error: ${e.message}');
      try {
        await client.pushDevError(code: code, message: e.message);
      } catch (_) {}
      return false;
    } on BackendException catch (e) {
      timer.stop();
      if (e.statusCode == 404) {
        Logger.error('Dev channel expired — restart "krom dev --remote".');
      } else {
        Logger.error('Push failed: ${e.message}');
      }
      return false;
    }
  }

  /// Prints the pairing code (primary — works on emulators) plus an optional
  /// `krom://dev` QR for a real phone.
  void _printRemoteTarget(String remoteUrl, DevChannel channel) {
    Logger.newline();
    Logger.info('Test on a device or emulator — no scan needed:');
    Logger.keyValue('Code', channel.displayCode);
    Logger.hint('Host app → Mode développeur → type this code.');

    final qr = terminalQr('krom://dev?u=$remoteUrl&c=${channel.code}');
    if (qr.isNotEmpty) {
      Logger.newline();
      Logger.info('…or scan on a real phone:');
      Logger.newline();
      stdout.write(qr);
      Logger.newline();
    }
  }
}
