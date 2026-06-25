import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:krom_script/krom_script.dart';
import 'package:krom_script/src/optimizer/optimizer.dart';
import 'package:krom_script/src/ast/ast_printer.dart';
import 'bundler.dart';
import 'manifest_validator.dart';

/// Manifest-based bundler for mini-app projects.
///
/// Reads a manifest.json, bundles all pages and components,
/// and generates a final manifest with inline scripts.
class ManifestBundler {
  final bool enableOptimizer;
  final bool minify;

  ManifestBundler({
    this.enableOptimizer = false,
    this.minify = false,
  });

  /// Create a fresh Bundler to avoid _processed state leaking between bundles.
  Bundler _freshBundler() => Bundler(enableOptimizer: false, minify: false);

  /// Bundle a mini-app project from its manifest.
  ///
  /// [manifestPath] - Path to manifest.json
  /// Returns the final manifest JSON as a string.
  Future<String> bundleProject(String manifestPath) async {
    final manifest = await bundleProjectToMap(manifestPath);
    if (minify) {
      return jsonEncode(manifest);
    }
    return const JsonEncoder.withIndent('  ').convert(manifest);
  }

  /// Bundle a mini-app project from its manifest, returning the compiled
  /// manifest as a map (the `app.json` object, scripts inlined).
  ///
  /// This is the structured form of [bundleProject]; callers that need to
  /// post-process the manifest (e.g. attach an `assets` integrity map for the
  /// version package) use this to avoid re-compiling.
  Future<Map<String, dynamic>> bundleProjectToMap(String manifestPath) async {
    final manifestFile = File(manifestPath);
    if (!await manifestFile.exists()) {
      throw BundlerException('Manifest not found: $manifestPath');
    }

    final manifestDir = p.dirname(p.absolute(manifestPath));
    final manifestContent = await manifestFile.readAsString();
    final manifest = jsonDecode(manifestContent) as Map<String, dynamic>;

    // Validate the manifest schema (window, tabBar, permissions/scopes,
    // networkTimeout, subpackages) before doing any bundling work, so the
    // user gets clear, fail-fast errors.
    ManifestValidator.validate(manifest);

    // Process utils first (they're shared)
    final utils = (manifest['utils'] as List<dynamic>?)?.cast<String>() ?? [];

    // Build the page -> subpackage-root assignment up front. A page listed in
    // a subpackage is bundled into that subpackage only; every other page
    // stays in the main package. This is the actual 分包 (subpackage) split
    // that enables on-demand loading, TCMPP/WeChat-style.
    final rawSubpackages = manifest['subpackages'] ?? manifest['subPackages'];
    final pageToSubpackage = _pageToSubpackageRoot(rawSubpackages);

    // Process pages, partitioning compiled output between the main package and
    // each subpackage. A page is never emitted in more than one place.
    final pagesInput = manifest['pages'] as Map<String, dynamic>? ?? {};
    final pagesOutput = <String, dynamic>{};
    // root -> { pageId -> compiledPage }
    final subpackagePages = <String, Map<String, dynamic>>{};

    for (final entry in pagesInput.entries) {
      final pageId = entry.key;
      final pageConfig = entry.value as Map<String, dynamic>;
      final sourcePath = pageConfig['source'] as String?;

      if (sourcePath == null) {
        throw BundlerException('Page "$pageId" missing "source" field');
      }

      final fullPath = p.join(manifestDir, sourcePath);
      final bundledScript =
          await _bundleWithUtils(fullPath, utils, manifestDir);

      final compiledPage = <String, dynamic>{
        'name': pageConfig['name'] ?? pageId,
        if (pageConfig['icon'] != null) 'icon': pageConfig['icon'],
        'script': bundledScript,
      };

      final root = pageToSubpackage[pageId];
      if (root != null) {
        (subpackagePages[root] ??= <String, dynamic>{})[pageId] = compiledPage;
      } else {
        pagesOutput[pageId] = compiledPage;
      }
    }

    // Process components
    final componentsInput =
        manifest['components'] as Map<String, dynamic>? ?? {};
    final componentsOutput = <String, dynamic>{};

    for (final entry in componentsInput.entries) {
      final componentId = entry.key;
      final componentConfig = entry.value as Map<String, dynamic>;
      final sourcePath = componentConfig['source'] as String?;

      if (sourcePath == null) {
        throw BundlerException(
            'Component "$componentId" missing "source" field');
      }

      final fullPath = p.join(manifestDir, sourcePath);
      final bundledScript =
          await _bundleWithUtils(fullPath, utils, manifestDir);

      componentsOutput[componentId] = {
        'name': componentConfig['name'] ?? componentId,
        'script': bundledScript,
      };
    }

    // Build the output subpackages: one entry per declared root, carrying its
    // own compiled pages. The runtime loads these on demand; pages here are
    // intentionally absent from the top-level "pages" map above.
    final subpackagesOutput = _buildSubpackagesOutput(
      rawSubpackages,
      subpackagePages,
    );

    // The main package's entry must live in the main package, never inside a
    // subpackage (TCMPP requires the entry page to load eagerly).
    final entry = manifest['entry'] ??
        (pagesOutput.isNotEmpty ? pagesOutput.keys.first : null);
    if (entry is String && pageToSubpackage.containsKey(entry)) {
      throw BundlerException(
          'Entry page "$entry" cannot be inside subpackage '
          '"${pageToSubpackage[entry]}"; the entry must stay in the main '
          'package so it loads on startup.');
    }

    // Build final manifest
    final outputManifest = <String, dynamic>{
      'id': manifest['id'],
      'name': manifest['name'],
      'version': manifest['version'],
      // The app icon is passed through so the runtime can render it and the
      // packager can collect it as an embedded asset.
      if (manifest['icon'] != null) 'icon': manifest['icon'],
      if (manifest['description'] != null)
        'description': manifest['description'],
      if (manifest['author'] != null) 'author': manifest['author'],
      if (manifest['license'] != null) 'license': manifest['license'],
      if (entry != null) 'entry': entry,
      'pages': pagesOutput,
      if (componentsOutput.isNotEmpty) 'components': componentsOutput,
      if (manifest['permissions'] != null)
        'permissions': manifest['permissions'],
      if (manifest['scopes'] != null) 'scopes': manifest['scopes'],
      if (manifest['authorizeUrl'] != null)
        'authorizeUrl': manifest['authorizeUrl'],
      // TCMPP-style configuration, passed through to the runtime.
      if (manifest['window'] != null) 'window': manifest['window'],
      if (manifest['tabBar'] != null) 'tabBar': manifest['tabBar'],
      if (manifest['networkTimeout'] != null)
        'networkTimeout': manifest['networkTimeout'],
      if (subpackagesOutput.isNotEmpty) 'subpackages': subpackagesOutput,
    };

    return outputManifest;
  }

  /// Flatten the declared subpackages into a `pageId -> root` lookup.
  ///
  /// Returns an empty map when there are no subpackages. The structure has
  /// already been validated by [ManifestValidator], so this assumes
  /// well-formed `{ root, pages: [...] }` entries.
  Map<String, String> _pageToSubpackageRoot(dynamic subpackages) {
    final result = <String, String>{};
    if (subpackages is! List) return result;
    for (final pkg in subpackages) {
      if (pkg is! Map) continue;
      final root = pkg['root'];
      final pages = pkg['pages'];
      if (root is! String || pages is! List) continue;
      for (final page in pages) {
        if (page is String) result[page] = root;
      }
    }
    return result;
  }

  /// Build the output `subpackages` list: each entry keeps its `root` (and any
  /// extra metadata the author set) and gains a `pages` map of *compiled*
  /// pages — exactly the pages that were pulled out of the main package.
  ///
  /// Output shape:
  /// ```json
  /// "subpackages": [
  ///   { "root": "packageStats",
  ///     "pages": { "stats_detail": { "name": ..., "script": ... } } }
  /// ]
  /// ```
  List<Map<String, dynamic>> _buildSubpackagesOutput(
    dynamic rawSubpackages,
    Map<String, Map<String, dynamic>> subpackagePages,
  ) {
    final output = <Map<String, dynamic>>[];
    if (rawSubpackages is! List) return output;

    for (final pkg in rawSubpackages) {
      if (pkg is! Map) continue;
      final root = pkg['root'];
      if (root is! String) continue;

      // Preserve any author-provided metadata (e.g. independent, plugins),
      // but replace the raw page-id list with the compiled pages map.
      final entry = <String, dynamic>{};
      for (final e in pkg.entries) {
        if (e.key == 'pages' || e.key == 'root') continue;
        entry[e.key.toString()] = e.value;
      }
      entry['root'] = root;
      entry['pages'] = subpackagePages[root] ?? <String, dynamic>{};
      output.add(entry);
    }
    return output;
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
    // Use a fresh bundler to avoid _processed state leaking between bundles
    final bundler = _freshBundler();
    final bundled = await bundler.bundle(filePath);
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
    await bundler.validate(finalSource);

    return finalSource;
  }

  /// Apply code optimizations
  String _optimize(String source) {
    try {
      final lexer = Lexer(source);
      final parser = Parser(lexer);
      final program = parser.parseProgram();

      if (parser.errors().isNotEmpty) {
        throw BundlerException(
            'Syntax Error(s) detected:\n${parser.errors().join('\n')}');
      }

      final optimizer = Optimizer(
          enableTreeShaking: true,
          enableInlining: true,
          enableConstantPropagation: true,
          enableDeadCodeElimination: true);
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
        RegExp(r'\s*([{}()\[\],;:])\s*'), (m) => '${m[1]}');
    result = result.replaceAllMapped(
        RegExp(r'\s*([=+\-*/<>!&|])\s*'), (m) => '${m[1]}');

    return result.trim();
  }
}
