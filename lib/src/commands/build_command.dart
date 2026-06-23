import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../bundler/bundler.dart';
import '../bundler/manifest_bundler.dart';
import '../utils/logger.dart';

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
      )
      ..addFlag(
        'split-subpackages',
        help: 'Write each subpackage to its own dist/subpackages/<root>.json '
            'file (in addition to the inline section of the main manifest).',
        defaultsTo: false,
      );
  }

  @override
  Future<int> run() async {
    final manifestPath = argResults!['manifest'] as String;
    final output = argResults!['output'] as String;
    final optimize = argResults!['optimize'] as bool;
    final minify = argResults!['minify'] as bool;
    final splitSubpackages = argResults!['split-subpackages'] as bool;
    final timer = Logger.startTimer();

    // Validate manifest exists
    if (!File(manifestPath).existsSync()) {
      Logger.bundleError(
        message: 'Manifest not found: $manifestPath',
        suggestion:
            'Run "krom init <name>" to create a new project, or use --manifest to specify the path.',
      );
      return 1;
    }

    Logger.header('Building mini-app');
    Logger.keyValue('Manifest', manifestPath);
    Logger.keyValue('Output', output);
    Logger.keyValue('Optimize', optimize ? 'enabled' : 'disabled');
    Logger.keyValue('Minify', minify ? 'enabled' : 'disabled');
    Logger.newline();

    try {
      Logger.step(1, 3, 'Reading manifest...');
      final bundler = ManifestBundler(
        enableOptimizer: optimize,
        minify: minify,
      );

      Logger.step(2, 3, 'Bundling pages & components...');
      final result = await bundler.bundleProject(manifestPath);

      Logger.step(3, 3, 'Writing output...');
      final outFile = File(output);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsString(result);

      // Optionally split each subpackage into its own file, mirroring the
      // TCMPP on-disk layout so the runtime can fetch a subpackage on demand.
      if (splitSubpackages) {
        await _writeSubpackageFiles(result, outFile.parent.path, minify);
      }

      timer.stop();

      // Count pages from the manifest
      final manifest = await _readManifest(manifestPath);
      final pageCount = (manifest['pages'] as Map?)?.length ?? 0;
      final componentCount = (manifest['components'] as Map?)?.length ?? 0;

      Logger.buildSummary(
        duration: timer.elapsed,
        pages: pageCount,
        components: componentCount,
        outputSize: outFile.lengthSync(),
        outputPath: output,
      );

      Logger.success('Build complete!');
      return 0;
    } on BundlerException catch (e) {
      timer.stop();
      Logger.bundleError(
        message: e.message,
        suggestion: 'Check your KromScript syntax and imports.',
      );
      return 1;
    } catch (e) {
      timer.stop();
      Logger.error('Build failed: $e');
      return 1;
    }
  }

  /// Write each compiled subpackage from [bundledManifestJson] to its own
  /// `<distDir>/subpackages/<root>.json` file. Each file contains the
  /// subpackage's `root` and its compiled `pages`.
  Future<void> _writeSubpackageFiles(
    String bundledManifestJson,
    String distDir,
    bool minify,
  ) async {
    final manifest =
        jsonDecode(bundledManifestJson) as Map<String, dynamic>;
    final subpackages = manifest['subpackages'];
    if (subpackages is! List || subpackages.isEmpty) return;

    final dir = Directory(p.join(distDir, 'subpackages'));
    await dir.create(recursive: true);

    final encoder =
        minify ? const JsonEncoder() : const JsonEncoder.withIndent('  ');

    for (final pkg in subpackages) {
      if (pkg is! Map) continue;
      final root = pkg['root'];
      if (root is! String) continue;
      final file = File(p.join(dir.path, '$root.json'));
      await file.writeAsString(encoder.convert(pkg));
      Logger.fileCreated(p.relative(file.path));
    }
  }

  Future<Map<String, dynamic>> _readManifest(String path) async {
    try {
      final content = await File(path).readAsString();
      return Map<String, dynamic>.from(jsonDecode(content) as Map);
    } catch (_) {
      return {};
    }
  }
}
