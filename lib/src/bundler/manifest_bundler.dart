import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:krom_script/krom_script.dart';
import 'package:krom_script/src/optimizer/optimizer.dart';
import 'package:krom_script/src/ast/ast_printer.dart';
import '../libs/known_libs.dart';
import '../utils/logger.dart';
import 'bundler.dart';
import 'manifest_validator.dart';
import 'minifier.dart';

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

  /// Host custom-widget names declared by the current project's manifest, plus
  /// the components of every domain lib it `requires`. Set at the start of
  /// [bundleProjectToMap]; consumed when validating each page so a top-level
  /// reference doesn't fail as "undefined".
  List<String> _customWidgets = const [];

  /// The domain packs the manifest declares in `requires`. Drives which lib
  /// components and modules are known during validation, and lets an
  /// undeclared-pack mistake be reported by name.
  List<String> _libPacks = const [];

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

    // Host custom widgets this app declares — stubbed during per-page
    // validation. Accepts a name array or an object map (name -> {docs}).
    final rawCustomWidgets = manifest['customWidgets'];
    final declaredWidgets = rawCustomWidgets is Map
        ? rawCustomWidgets.keys.map((e) => e.toString()).toList()
        : (rawCustomWidgets as List<dynamic>?)
                ?.map((e) => e.toString())
                .toList() ??
            const <String>[];

    // Domain libs are embedded in the CLI: declaring a pack in `requires` is
    // enough for its components to be known here, exactly as if they were core.
    // Listing them again under `customWidgets` stays valid but is unnecessary.
    _libPacks = ((manifest['requires'] as List<dynamic>?) ?? const [])
        .map((e) => e.toString())
        .where(KnownLibs.packs.contains)
        .toList();
    _customWidgets = {
      ...declaredWidgets,
      ...KnownLibs.componentsFor(_libPacks),
    }.toList();

    // Imports are on-demand: each page/component pulls exactly the utilities it
    // `@use`s (transitively), nothing more. The legacy top-level `utils` list
    // (which used to be force-prepended to every page) is no longer
    // auto-combined — warn if a manifest still relies on it.
    final legacyUtils =
        (manifest['utils'] as List<dynamic>?)?.cast<String>() ?? [];
    if (legacyUtils.isNotEmpty) {
      Logger.warn(
        'manifest "utils" is deprecated and no longer auto-imported. '
        'Add `@use "<path>"` to each page/component that needs them.',
      );
    }

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
      final bundledScript = await _bundlePage(fullPath);

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
      final bundledScript = await _bundlePage(fullPath);

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
      // Les packs de capacité exigés, et la version de SDK minimale. Sans eux
      // dans la sortie, le runtime ne peut ni refuser proprement une mini-app
      // dont l'hôte n'a pas branché la lib, ni lui accorder le pack déclaré :
      // les composants resteraient introuvables à l'exécution.
      if (manifest['requires'] != null) 'requires': manifest['requires'],
      if (manifest['minSdk'] != null) 'minSdk': manifest['minSdk'],
      // Passed through so a host without the real builder (e.g. the web preview)
      // can render a labeled placeholder instead of "Unknown widget".
      if (manifest['customWidgets'] != null)
        'customWidgets': manifest['customWidgets'],
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

  /// Bundle a page/component file by resolving only its `@use` imports.
  ///
  /// Nothing is imported implicitly: the file gets exactly the utilities it
  /// `@use`s (resolved transitively, de-duplicated, with circular-import
  /// detection by [Bundler]). Optimisation/minification run once on the
  /// resolved unit.
  Future<String> _bundlePage(String filePath) async {
    // The inner bundler only resolves @use imports and strips the directives;
    // it does no optimisation itself, so we optimise/minify here exactly once.
    final bundler = _freshBundler();
    var finalSource = await bundler.bundle(filePath);

    if (enableOptimizer) {
      finalSource = _optimize(finalSource);
    }

    if (minify) {
      finalSource = _minify(finalSource);
    }

    // Les libs sont connues du binaire : utiliser un de leurs composants sans
    // déclarer son pack est donc une erreur qu'on peut nommer ici. La
    // validation ci-dessous n'exécute que le code de premier niveau et ne la
    // verrait pas — elle passerait inaperçue jusqu'à un écran vide.
    final undeclared = KnownLibs.undeclaredUsage(finalSource, _libPacks);
    if (undeclared.isNotEmpty) {
      throw BundlerException(KnownLibs.messageForUndeclaredUsage(undeclared));
    }

    try {
      await bundler.validate(
        finalSource,
        customWidgets: _customWidgets,
        modulePrelude: KnownLibs.moduleStubFor(_libPacks),
      );
    } on BundlerException catch (e) {
      // La faute la plus probable : un composant de lib utilisé sans avoir
      // déclaré son pack. Le moteur ne dit alors qu'« undefined variable » —
      // on nomme le pack et la clé à corriger.
      final hint = KnownLibs.hintForUndeclared(e.message, _libPacks);
      if (hint == null) rethrow;
      throw BundlerException('${e.message}\n\n$hint');
    }

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

  /// Minify the combined source — string-literal-aware (see [minifyKromSource]).
  String _minify(String source) => minifyKromSource(source);
}
