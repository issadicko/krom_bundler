import 'dart:async';
import 'dart:io';
import 'package:args/command_runner.dart';
import '../server/dev_server.dart';
import '../bundler/bundler.dart';
import '../bundler/manifest_bundler.dart';
import '../utils/logger.dart';

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
        help: 'Server host',
        defaultsTo: 'localhost',
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
}
