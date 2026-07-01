import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:krom_script/krom_script.dart';
import 'package:krom_script/src/optimizer/optimizer.dart';
import 'package:krom_script/src/ast/ast_printer.dart';
import '../utils/logger.dart';
import 'minifier.dart';

/// Bundler - bundles KromLang scripts with @use imports
class Bundler {
  final bool enableOptimizer;
  final bool minify;
  final Set<String> _processed = {};
  final Set<String> _inProgress = {}; // For circular detection
  final StringBuffer _output = StringBuffer();

  Bundler({this.enableOptimizer = false, this.minify = false});

  /// Bundle the entry file and all its dependencies
  Future<String> bundle(String entryPath) async {
    _processed.clear();
    _inProgress.clear();
    _output.clear();

    await _processFile(entryPath, [entryPath]);

    var result = _output.toString();

    // Apply optimizations
    if (enableOptimizer) {
      result = _optimize(result);
    }

    if (minify) {
      result = _minify(result);
    }

    return result;
  }

  Future<void> _processFile(String filePath, List<String> importStack) async {
    final absolutePath = p.absolute(filePath);

    // Circular dependency detection
    if (_inProgress.contains(absolutePath)) {
      final cycle = [...importStack, p.basename(absolutePath)].join(' → ');
      throw BundlerException('Circular dependency detected: $cycle');
    }

    // Skip if already processed
    if (_processed.contains(absolutePath)) return;

    _inProgress.add(absolutePath);

    final file = File(absolutePath);
    if (!await file.exists()) {
      final parent =
          importStack.length > 1 ? importStack[importStack.length - 2] : null;
      throw BundlerException(
        'File not found: $filePath'
        '${parent != null ? '\n  imported from: $parent' : ''}',
      );
    }

    final source = await file.readAsString();
    final baseDir = p.dirname(absolutePath);

    // Extract and process imports
    final imports = _extractImports(source);
    for (final import in imports) {
      final importPath = _resolveImportPath(import, baseDir);
      await _processFile(importPath, [...importStack, p.basename(importPath)]);
    }

    // Remove import statements and add processed source
    final cleanedSource = _removeImports(source);

    _output.writeln('// === ${p.basename(absolutePath)} ===');
    _output.writeln(cleanedSource);
    _output.writeln();

    _inProgress.remove(absolutePath);
    _processed.add(absolutePath);
  }

  /// Extract @use import paths from source
  List<String> _extractImports(String source) {
    final imports = <String>[];
    final regex = RegExp(r'@use\s+"([^"]+)"');

    for (final match in regex.allMatches(source)) {
      imports.add(match.group(1)!);
    }
    return imports;
  }

  /// Resolve import path relative to current file
  String _resolveImportPath(String importPath, String baseDir) {
    var resolved = importPath;
    if (!resolved.endsWith('.ks')) {
      resolved = '$resolved.ks';
    }

    if (resolved.startsWith('./') || resolved.startsWith('../')) {
      return p.normalize(p.join(baseDir, resolved));
    }

    return p.normalize(p.join(baseDir, resolved));
  }

  /// Remove @use statements from source
  String _removeImports(String source) {
    return source.replaceAll(RegExp(r'@use\s+"[^"]+"\s*\n?'), '');
  }

  /// Apply code optimizations
  String _optimize(String source) {
    // 1. AST-based optimization (Constant Folding + Tree Shaking)
    try {
      final lexer = Lexer(source);
      final parser = Parser(lexer);
      final program = parser.parseProgram();

      if (parser.errors().isNotEmpty) {
        throw BundlerException(
            'Syntax Error(s) detected:\n${parser.errors().join('\n')}');
      }

      final optimizer = Optimizer(
          enableTreeShaking: true, // Enabled: now smarter about callbacks
          enableInlining: false, // Keep disabled for now to be safe
          enableConstantPropagation: true,
          enableDeadCodeElimination: true // Enabled: should be safe now
          );

      final optimizedProgram = optimizer.optimize(program);
      final printer = ASTPrinter();
      return printer.print(optimizedProgram);
    } catch (e) {
      if (e is BundlerException) rethrow;
      // If optimization fails but parsing succeeded (e.g. optimizer bug), maybe warn?
      // But user asked for strict failure on syntax errors.
      // The parser checks above cover syntax errors.
      // Any other error here is likely an internal tool error.
      // Let's rethrow to be safe and strict as requested.
      throw BundlerException('Optimization failed: $e');
    }
  }

  /// Minify the source — string-literal-aware (see [minifyKromSource]).
  String _minify(String source) => minifyKromSource(source);

  /// A default Material 3 light `theme` map mirroring what the kmini_program
  /// runtime injects, so validation can execute top-level code that builds a
  /// palette from `theme.*` (e.g. `let T = { primary: theme.primary }`).
  static const Map<String, Object?> _defaultThemeVars = {
    'brightness': 'light',
    'primary': '#6750A4', 'onPrimary': '#FFFFFF',
    'primaryContainer': '#EADDFF', 'onPrimaryContainer': '#21005D',
    'secondary': '#625B71', 'onSecondary': '#FFFFFF',
    'secondaryContainer': '#E8DEF8', 'onSecondaryContainer': '#1D192B',
    'tertiary': '#7D5260', 'onTertiary': '#FFFFFF',
    'surface': '#FEF7FF', 'onSurface': '#1D1B20', 'onSurfaceVariant': '#49454F',
    'surfaceContainerLowest': '#FFFFFF', 'surfaceContainerLow': '#F7F2FA',
    'surfaceContainer': '#F3EDF7', 'surfaceContainerHigh': '#ECE6F0',
    'surfaceContainerHighest': '#E6E0E9',
    'inverseSurface': '#322F35', 'onInverseSurface': '#F5EFF7',
    'inversePrimary': '#D0BCFF',
    'error': '#B3261E', 'onError': '#FFFFFF',
    'errorContainer': '#F9DEDC', 'onErrorContainer': '#410E0B',
    'outline': '#79747E', 'outlineVariant': '#CAC4D0',
  };

  /// Validate bundled output by parsing it.
  ///
  /// [customWidgets] are host-provided widget names declared in the manifest;
  /// they're stubbed so a top-level reference validates instead of throwing
  /// "undefined variable" (the runtime injects the real builders).
  Future<void> validate(
    String bundledSource, {
    List<String> customWidgets = const [],
  }) async {
    final engine = KSEngine();
    // Stub host-injected globals so top-level code that reads them (the
    // `theme` palette idiom, or `args`) validates instead of throwing
    // "undefined variable". The runtime binds the real values.
    engine.setVariable('theme', _defaultThemeVars);
    engine.setVariable('args', null);

    // Stub declared host custom widgets as no-op builders. Prepended for the
    // validation load only — the emitted source is unchanged.
    final stub = customWidgets
        .map((n) => 'let $n = fn(props, children) { return null }')
        .join('\n');
    final source = stub.isEmpty ? bundledSource : '$stub\n$bundledSource';

    final result = await engine.load(source, enableOptimizer: false);
    if (!result.success) {
      Logger.debug('Validation errors: ${result.errors}');
      throw BundlerException(
          'Validation failed:\n  ${result.errors.join('\n  ')}');
    }
  }
}

/// Exception thrown by bundler
class BundlerException implements Exception {
  final String message;
  BundlerException(this.message);

  @override
  String toString() => 'BundlerException: $message';
}
