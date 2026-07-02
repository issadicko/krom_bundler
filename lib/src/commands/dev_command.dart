import 'dart:async';
import 'dart:io';
import 'package:args/command_runner.dart';
import '../server/dev_server.dart';
import '../bundler/bundler.dart';
import '../bundler/manifest_bundler.dart';
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
}
