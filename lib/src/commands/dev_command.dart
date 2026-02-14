import 'dart:async';
import 'dart:io';
import 'package:args/command_runner.dart';
import '../server/dev_server.dart';
import '../bundler/manifest_bundler.dart';

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
    final port = int.parse(argResults!['port'] as String);
    final host = argResults!['host'] as String;

    // Verify manifest exists
    if (!File(manifestPath).existsSync()) {
      print('❌ Manifest not found: $manifestPath');
      print('   Create a manifest.json file to define your mini-app.');
      return 1;
    }

    print('🚀 Starting Krom dev server...');
    print('   Manifest: $manifestPath');
    print('   URL: http://$host:$port');
    print('');

    try {
      final bundler = ManifestBundler();
      final server = DevServer(
        manifestBundler: bundler,
        manifestPath: manifestPath,
        host: host,
        port: port,
      );

      await server.start();

      print('✅ Dev server running at http://$host:$port');
      print('   Watching for changes... (Ctrl+C to stop)');

      // Keep running until interrupted
      await ProcessSignal.sigint.watch().first;
      
      print('\n🛑 Shutting down...');
      await server.stop();
      
      return 0;
    } catch (e) {
      print('❌ Dev server failed: $e');
      return 1;
    }
  }
}
