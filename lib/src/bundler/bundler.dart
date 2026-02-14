import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:krom_script/krom_script.dart';
import 'package:krom_script/src/optimizer/optimizer.dart';
import 'package:krom_script/src/ast/ast_printer.dart';

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
      throw BundlerException('File not found: $filePath');
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

  /// Minify code (remove all unnecessary whitespace)
  String _minify(String source) {
    var result = source;

    // Remove all comments
    result = result.replaceAll(RegExp(r'//.*$', multiLine: true), '');

    // Remove newlines and extra spaces
    result = result.replaceAll(RegExp(r'\s+'), ' ');

    // Remove spaces around operators and punctuation
    result = result.replaceAll(RegExp(r'\s*([{}()\[\],;:])\s*'), r'$1');
    result = result.replaceAll(RegExp(r'\s*([=+\-*/<>!&|])\s*'), r'$1');

    return result.trim();
  }

  /// Validate bundled output by parsing it
  Future<void> validate(String bundledSource) async {
    final engine = KSEngine();
    final result = await engine.load(bundledSource, enableOptimizer: false);
    print(result.errors);
    if (!result.success) {
      throw BundlerException('Validation failed: ${result.errors}');
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
