import 'dart:io';
import 'package:args/command_runner.dart';
import '../bundler/bundler.dart';

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
      );
  }

  @override
  Future<int> run() async {
    final entry = argResults!['entry'] as String;
    final output = argResults!['output'] as String;

    print('📦 Bundling $entry → $output');

    try {
      final bundler = Bundler();
      final result = await bundler.bundle(entry);

      // Ensure output directory exists
      final outFile = File(output);
      await outFile.parent.create(recursive: true);
      await outFile.writeAsString(result);

      print('✅ Bundle created: $output');
      return 0;
    } catch (e) {
      print('❌ Bundle failed: $e');
      return 1;
    }
  }
}
