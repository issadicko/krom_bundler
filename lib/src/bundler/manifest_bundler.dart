import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:krom_script/krom_script.dart';
import 'package:krom_script/src/optimizer/optimizer.dart';
import 'package:krom_script/src/ast/ast_printer.dart';
import 'bundler.dart';

/// Manifest-based bundler for mini-app projects.
/// 
/// Reads a manifest.json, bundles all pages and components,
/// and generates a final manifest with inline scripts.
class ManifestBundler {
  final bool enableOptimizer;
  final bool minify;
  final Bundler _bundler;

  ManifestBundler({
    this.enableOptimizer = false, 
    this.minify = false,
  }) : _bundler = Bundler(enableOptimizer: false, minify: false);

  /// Bundle a mini-app project from its manifest.
  /// 
  /// [manifestPath] - Path to manifest.json
  /// Returns the final manifest JSON as a string.
  Future<String> bundleProject(String manifestPath) async {
    final manifestFile = File(manifestPath);
    if (!await manifestFile.exists()) {
      throw BundlerException('Manifest not found: $manifestPath');
    }

    final manifestDir = p.dirname(p.absolute(manifestPath));
    final manifestContent = await manifestFile.readAsString();
    final manifest = jsonDecode(manifestContent) as Map<String, dynamic>;

    // Process utils first (they're shared)
    final utils = (manifest['utils'] as List<dynamic>?)?.cast<String>() ?? [];
    
    // Process pages
    final pagesInput = manifest['pages'] as Map<String, dynamic>? ?? {};
    final pagesOutput = <String, dynamic>{};
    
    for (final entry in pagesInput.entries) {
      final pageId = entry.key;
      final pageConfig = entry.value as Map<String, dynamic>;
      final sourcePath = pageConfig['source'] as String?;
      
      if (sourcePath == null) {
        throw BundlerException('Page "$pageId" missing "source" field');
      }

      final fullPath = p.join(manifestDir, sourcePath);
      final bundledScript = await _bundleWithUtils(fullPath, utils, manifestDir);

      pagesOutput[pageId] = {
        'name': pageConfig['name'] ?? pageId,
        if (pageConfig['icon'] != null) 'icon': pageConfig['icon'],
        'script': bundledScript,
      };
    }

    // Process components
    final componentsInput = manifest['components'] as Map<String, dynamic>? ?? {};
    final componentsOutput = <String, dynamic>{};

    for (final entry in componentsInput.entries) {
      final componentId = entry.key;
      final componentConfig = entry.value as Map<String, dynamic>;
      final sourcePath = componentConfig['source'] as String?;

      if (sourcePath == null) {
        throw BundlerException('Component "$componentId" missing "source" field');
      }

      final fullPath = p.join(manifestDir, sourcePath);
      final bundledScript = await _bundleWithUtils(fullPath, utils, manifestDir);

      componentsOutput[componentId] = {
        'name': componentConfig['name'] ?? componentId,
        'script': bundledScript,
      };
    }

    // Build final manifest
    final outputManifest = <String, dynamic>{
      'id': manifest['id'],
      'name': manifest['name'],
      'version': manifest['version'],
      if (manifest['description'] != null) 'description': manifest['description'],
      if (manifest['author'] != null) 'author': manifest['author'],
      if (manifest['license'] != null) 'license': manifest['license'],
      'entry': manifest['entry'] ?? pagesOutput.keys.first,
      'pages': pagesOutput,
      if (componentsOutput.isNotEmpty) 'components': componentsOutput,
      if (manifest['permissions'] != null) 'permissions': manifest['permissions'],
      if (manifest['authorizeUrl'] != null) 'authorizeUrl': manifest['authorizeUrl'],
    };

    if (minify) {
      return jsonEncode(outputManifest);
    }
    return const JsonEncoder.withIndent('  ').convert(outputManifest);
  }

  /// Bundle a file with all utils prepended.
  Future<String> _bundleWithUtils(
    String filePath, 
    List<String> utils, 
    String manifestDir,
  ) async {
    final buffer = StringBuffer();

    // First, include all utils
    for (final utilPath in utils) {
      final fullUtilPath = p.join(manifestDir, utilPath);
      final utilFile = File(fullUtilPath);
      if (await utilFile.exists()) {
        buffer.writeln('// ===== ${p.basename(utilPath)} =====');
        buffer.writeln(await utilFile.readAsString());
        buffer.writeln();
      }
    }

    // Then bundle the main file (which may have its own @use imports)
    final bundled = await _bundler.bundle(filePath);
    buffer.writeln('// ===== ${p.basename(filePath)} =====');
    buffer.write(bundled);

    var finalSource = buffer.toString();

    // Now apply optimization globally on the combined source!
    if (enableOptimizer) {
      finalSource = _optimize(finalSource);
    }

    // Apply minification
    if (minify) {
      finalSource = _minify(finalSource);
    }

    // Validate the bundled output
    await _bundler.validate(finalSource);

    return finalSource;
  }

  /// Apply code optimizations
  String _optimize(String source) {
    try {
      final lexer = Lexer(source);
      final parser = Parser(lexer);
      final program = parser.parseProgram();
      
      if (parser.errors().isNotEmpty) {
         throw BundlerException('Syntax Error(s) detected:\n${parser.errors().join('\n')}');
      }

      final optimizer = Optimizer(
        enableTreeShaking: true,
        enableInlining: true, 
        enableConstantPropagation: true,
        enableDeadCodeElimination: true
      );
      final optimizedProgram = optimizer.optimize(program);
      final printer = ASTPrinter();
      return printer.print(optimizedProgram);

    } catch (e) {
      if (e is BundlerException) rethrow;
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
    result = result.replaceAllMapped(
      RegExp(r'\s*([{}()\[\],;:])\s*'), 
      (m) => '${m[1]}'
    );
    result = result.replaceAllMapped(
      RegExp(r'\s*([=+\-*/<>!&|])\s*'), 
      (m) => '${m[1]}'
    );
    
    return result.trim();
  }
}
