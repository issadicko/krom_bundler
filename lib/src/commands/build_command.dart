import 'dart:io';
import 'package:args/command_runner.dart';
import '../bundler/manifest_bundler.dart';

/// Build command - production build from manifest.json
class BuildCommand extends Command<int> {
  @override
  final name = 'build';

  @override
  final description = 'Build KromLang mini-app for production';

  BuildCommand() {
    argParser
      ..addOption(
        'manifest',
        abbr: 'm',
        help: 'Path to manifest.json',
        defaultsTo: 'manifest.json',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output file path',
        defaultsTo: 'dist/manifest.json',
      )
      ..addFlag(
        'optimize',
        help: 'Enable constant folding optimization',
        defaultsTo: true,
      )
      ..addFlag(
        'minify',
        help: 'Minify output (remove comments and whitespace)',
        defaultsTo: false,
      );
  }

  @override
  Future<int> run() async {
    final manifestPath = argResults!['manifest'] as String;
    final output = argResults!['output'] as String;
    final optimize = argResults!['optimize'] as bool;

    print('🔨 Building mini-app from $manifestPath...');
    if (optimize) print('   Optimizations enabled');

    try {
      final bundler = ManifestBundler(
        enableOptimizer: optimize,
        minify: argResults!['minify'] as bool,
      );
      final result = await bundler.bundleProject(manifestPath);

      // Ensure output directory exists
      final outFile = File(output);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsString(result);

      print('✅ Build complete: $output');
      return 0;
    } catch (e) {
      print('❌ Build failed: $e');
      return 1;
    }
  }
}
