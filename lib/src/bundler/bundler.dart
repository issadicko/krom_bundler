import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:krom_script/krom_script.dart';
import 'package:krom_script/src/optimizer/optimizer.dart';
import 'package:krom_script/src/ast/ast_printer.dart';
import '../utils/logger.dart';
import 'minifier.dart';
import 'module_scope.dart';
import 'source_map.dart';

/// A file pulled into a bundle, with what the graph learned about it.
class BundledModule {
  final String path;
  final String cleanedSource;
  final List<KromImport> imports;
  final ModuleSurface surface;

  /// Aliases importers gave this module. Empty for the entry file and for a
  /// module every importer pulled in flat.
  final Set<String> aliases = {};

  /// Whether some importer used the historical form, without `as`.
  bool importedFlat = false;

  /// Number of `@use` directives pointing at this module across the graph.
  int importCount = 0;

  BundledModule({
    required this.path,
    required this.cleanedSource,
    required this.imports,
    required this.surface,
  });

  bool get isScoped => aliases.isNotEmpty;
}

/// Bundler - bundles KromLang scripts with @use imports
class Bundler {
  final bool enableOptimizer;
  final bool minify;

  /// Names the host injects or the prelude declares. An alias may not take one
  /// of them: the module would win the lookup and the widget would vanish.
  final Set<String> reservedNames;

  final Set<String> _inProgress = {}; // For circular detection
  final StringBuffer _output = StringBuffer();
  final List<BundleSegment> _segments = [];

  /// Modules in dependency-first order, keyed by absolute path.
  final Map<String, BundledModule> _modules = {};

  /// The modules of the last [bundle], dependency-first. The entry file is
  /// last. Read by the duplication report.
  List<BundledModule> get modules => List.unmodifiable(_modules.values);

  /// Prochaine ligne à écrire dans [_output], 1-indexée.
  int _line = 1;

  /// Où retombe chaque ligne du dernier [bundle] dans les fichiers du projet.
  ///
  /// Ne vaut que pour la concaténation brute : optimisation et minification
  /// réécrivent le texte et rendent la table caduque.
  BundleSourceMap? _sourceMap;
  BundleSourceMap? get sourceMap => _sourceMap;

  /// Racine du projet, pour que [sourceMap] affiche `pages/home.ks` plutôt
  /// qu'un chemin absolu. `null` : le dossier du fichier d'entrée.
  final String? projectRoot;

  Bundler({
    this.enableOptimizer = false,
    this.minify = false,
    this.projectRoot,
    this.reservedNames = const {},
  });

  /// Bundle the entry file and all its dependencies
  Future<String> bundle(String entryPath) async {
    _inProgress.clear();
    _modules.clear();
    _output.clear();
    _segments.clear();
    _line = 1;

    await _collect(entryPath, [entryPath]);
    _checkScopes();
    _emit();

    _sourceMap = BundleSourceMap(
      List.unmodifiable(_segments),
      root: projectRoot ?? p.dirname(p.absolute(entryPath)),
    );

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

  /// Walk the import graph from [filePath], registering each file once and in
  /// dependency-first order. Nothing is written here: aliases are only fully
  /// known once every importer has been seen.
  Future<void> _collect(String filePath, List<String> importStack) async {
    final absolutePath = p.absolute(filePath);

    // Circular dependency detection
    if (_inProgress.contains(absolutePath)) {
      final cycle = [...importStack, p.basename(absolutePath)].join(' → ');
      throw BundlerException('Circular dependency detected: $cycle');
    }

    // Already registered: its aliases were recorded by the caller.
    if (_modules.containsKey(absolutePath)) return;

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
    final cleanedSource = stripImports(source);
    final imports = parseImports(source);

    // A file that does not parse gets an empty surface rather than an error
    // here: syntax is reported once, by the validation pass, which situates it
    // through the source map. Failing early would just say the same thing
    // twice, in two formats.
    ModuleSurface surface;
    try {
      surface = analyzeSource(cleanedSource);
    } on ModuleParseException {
      surface = const ModuleSurface(exports: [], freeNames: {});
    }

    for (final import in imports) {
      final importPath = _resolveImportPath(import.path, baseDir);
      await _collect(importPath, [...importStack, p.basename(importPath)]);

      final imported = _modules[p.absolute(importPath)];
      if (imported == null) continue; // cycle already reported
      imported.importCount++;
      if (import.alias == null) {
        imported.importedFlat = true;
      } else {
        imported.aliases.add(import.alias!);
      }
    }

    _inProgress.remove(absolutePath);
    // Registered after its dependencies so iteration order is dependency-first.
    _modules[absolutePath] = BundledModule(
      path: absolutePath,
      cleanedSource: cleanedSource,
      imports: imports,
      surface: surface,
    );
  }

  /// Reject the alias mistakes that would otherwise surface as a silent
  /// wrong-value at runtime.
  void _checkScopes() {
    // alias -> module that owns it
    final owners = <String, BundledModule>{};

    for (final module in _modules.values) {
      if (module.importedFlat && module.isScoped) {
        throw BundlerException(
          '${_relative(module.path)} is imported both ways: with `as '
          '${module.aliases.first}` and without. Pick one — a module is either '
          'scoped or flat, not both.',
        );
      }

      for (final alias in module.aliases) {
        if (reservedNames.contains(alias)) {
          throw BundlerException(
            'Alias "$alias" for ${_relative(module.path)} is already a widget '
            'or a host namespace. Choose another name.',
          );
        }
        final owner = owners[alias];
        if (owner != null && owner.path != module.path) {
          throw BundlerException(
            'Alias "$alias" names two different modules: '
            '${_relative(owner.path)} and ${_relative(module.path)}.',
          );
        }
        owners[alias] = module;
      }
    }

    // An alias belongs to the file that imported it. The runtime bundle is
    // flat, so nothing would stop a file from reading someone else's alias —
    // and code that relied on it would break the day modules become real.
    for (final module in _modules.values) {
      final own = module.imports
          .where((i) => i.alias != null)
          .map((i) => i.alias!)
          .toSet();
      for (final name in module.surface.freeNames) {
        final owner = owners[name];
        if (owner == null || own.contains(name)) continue;
        if (owner.path == module.path) continue;
        throw BundlerException(
          '${_relative(module.path)} uses "$name", which is the alias '
          '${_relative(owner.path)} was imported under somewhere else.\n'
          '  Add `@use "<path>" as $name` to this file to use it here.',
        );
      }
    }
  }

  /// Write the collected modules out, wrapping the scoped ones.
  void _emit() {
    for (final module in _modules.values) {
      _output.writeln('// === ${p.basename(module.path)} ===');
      _line++;

      final internal = module.isScoped ? _internalName(module.path) : null;
      if (internal != null) {
        _output.writeln('let $internal = fn() {');
        _line++;
      }

      final lineCount = countLines(module.cleanedSource);
      _segments.add(BundleSegment(
        path: module.path,
        bundleStart: _line,
        lineCount: lineCount,
      ));
      _output.writeln(module.cleanedSource);
      _line += lineCount;

      if (internal != null) {
        final exports =
            module.surface.exports.map((name) => '$name: $name').join(', ');
        _output.writeln('return { $exports }');
        _output.writeln('}()');
        _line += 2;
        for (final alias in module.aliases) {
          _output.writeln('let $alias = $internal');
          _line++;
        }
      }

      _output.writeln();
      _line++;
    }
  }

  /// The bundle-private name holding a scoped module's exports. Derived from
  /// the path so two files with the same basename stay apart, and emitted once
  /// however many aliases point at it.
  String _internalName(String absolutePath) {
    final relative = _relative(absolutePath).replaceAll(RegExp(r'\.ks$'), '');
    return '__m_${relative.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_')}';
  }

  String _relative(String absolutePath) {
    final root = projectRoot;
    if (root == null) return p.basename(absolutePath);
    return p.relative(absolutePath, from: root);
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

  /// Apply code optimizations
  String _optimize(String source) {
    // 1. AST-based optimization (Constant Folding + Tree Shaking)
    try {
      final lexer = Lexer(source);
      final parser = Parser(lexer);
      final program = parser.parseProgram();

      if (parser.errors().isNotEmpty) {
        throw BundlerException(remapBundleErrors(
          'Syntax Error(s) detected:\n${parser.errors().join('\n')}',
          _sourceMap,
        ));
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
  /// [customWidgets] are host-provided widget names declared in the manifest —
  /// plus, since the CLI embeds their descriptors, the components of every
  /// domain lib the manifest `requires`. They're stubbed so a top-level
  /// reference validates instead of throwing "undefined variable" (the runtime
  /// injects the real builders).
  ///
  /// [modulePrelude] is raw KromScript stubbing host namespaces (`charts`,
  /// `media`, …) so a top-level call to one of them validates too. At runtime
  /// the bindings are injected *before* the script loads, so such a call has
  /// always been legal — only the bundler could not see it.
  /// [sourceMap] situe les erreurs dans les fichiers du projet. Ne la passer
  /// que si [bundledSource] est bien la concaténation brute : optimisation et
  /// minification réécrivent le texte, et la table ne vaut plus rien.
  Future<void> validate(
    String bundledSource, {
    List<String> customWidgets = const [],
    String modulePrelude = '',
    BundleSourceMap? sourceMap,
  }) async {
    final engine = KSEngine();
    // Stub host-injected globals so top-level code that reads them (the
    // `theme` palette idiom, or `args`) validates instead of throwing
    // "undefined variable". The runtime binds the real values.
    engine.setVariable('theme', _defaultThemeVars);
    engine.setVariable('args', null);

    // Stub declared host custom widgets as no-op builders. Prepended for the
    // validation load only — the emitted source is unchanged.
    final stub = [
      ...customWidgets
          .map((n) => 'let $n = fn(props, children) { return null }'),
      if (modulePrelude.trim().isNotEmpty) modulePrelude.trim(),
    ].join('\n');
    final source = stub.isEmpty ? bundledSource : '$stub\n$bundledSource';

    final result = await engine.load(source, enableOptimizer: false);
    if (!result.success) {
      Logger.debug('Validation errors: ${result.errors}');
      throw BundlerException(remapBundleErrors(
        'Validation failed:\n  ${result.errors.join('\n  ')}',
        sourceMap,
        // Les stubs sont écrits devant le bundle : le moteur compte à partir
        // d'eux, pas du premier fichier du projet.
        preludeLines: stub.isEmpty ? 0 : countLines(stub),
      ));
    }
  }
}

/// [message] avec ses positions ramenées aux fichiers du projet, ou tel quel
/// quand aucune table ne s'applique — après optimisation, par exemple.
String remapBundleErrors(
  String message,
  BundleSourceMap? sourceMap, {
  int preludeLines = 0,
}) =>
    sourceMap == null
        ? message
        : sourceMap.remap(message, preludeLines: preludeLines);

/// Exception thrown by bundler
class BundlerException implements Exception {
  final String message;
  BundlerException(this.message);

  @override
  String toString() => 'BundlerException: $message';
}
