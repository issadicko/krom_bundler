import 'dart:io';
import 'package:args/command_runner.dart';
import '../bundler/bundler.dart';
import '../utils/logger.dart';

/// Bundle command - bundles KromLang files into a single file
class BundleCommand extends Command<int> {
  @override
  final name = 'bundle';

  @override
  final description = 'Bundle KromLang files into a single output file';

  BundleCommand() {
    argParser
      ..addOption(
        'entry',
        abbr: 'e',
        help: 'Entry file path',
        defaultsTo: 'main.ks',
      )
      ..addOption(
        'output',
        abbr: 'o',
        help: 'Output file path',
        defaultsTo: 'dist/bundle.ks',
      )
      ..addFlag(
        'optimize',
        help: 'Enable code optimization',
        defaultsTo: false,
      )
      ..addFlag(
        'minify',
        help: 'Minify output',
        defaultsTo: false,
      );
  }

  @override
  Future<int> run() async {
    final entry = argResults!['entry'] as String;
    final output = argResults!['output'] as String;
    final optimize = argResults!['optimize'] as bool;
    final minify = argResults!['minify'] as bool;
    final timer = Logger.startTimer();

    // Validate entry file
    if (!File(entry).existsSync()) {
      Logger.bundleError(
        message: 'Entry file not found: $entry',
        suggestion: 'Use --entry to specify the entry file path.',
      );
      return 1;
    }

    Logger.header('Bundling');
    Logger.keyValue('Entry', entry);
    Logger.keyValue('Output', output);
    Logger.newline();

    try {
      Logger.step(1, 2, 'Resolving imports & bundling...');
      final bundler = Bundler(enableOptimizer: optimize, minify: minify);
      final result = await bundler.bundle(entry);

      Logger.step(2, 2, 'Writing output...');
      final outFile = File(output);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsString(result);

      timer.stop();

      Logger.newline();
      Logger.keyValue('Duration', Logger.formatDuration(timer.elapsed));
      Logger.keyValue('Output size', Logger.formatSize(outFile.lengthSync()));
      Logger.newline();
      Logger.success('Bundle created: $output');
      return 0;
    } on BundlerException catch (e) {
      timer.stop();
      Logger.bundleError(
        message: e.message,
        suggestion: 'Check your KromScript imports and file paths.',
      );
      return 1;
    } catch (e) {
      timer.stop();
      Logger.error('Bundle failed: $e');
      return 1;
    }
  }
}
