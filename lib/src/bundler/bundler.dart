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

  /// Chemin d'import tel qu'écrit -> fichier absolu qu'il désigne. Rempli à
  /// la collecte : l'émission relie chaque import sans avoir à re-résoudre.
  final Map<String, String> resolvedImports;

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
    required this.resolvedImports,
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

  /// Racines des dépendances .ks déclarées, nom → dossier absolu. Un import
  /// nu dont le premier segment est l'une d'elles se résout dans la
  /// dépendance, pas relativement au fichier.
  final Map<String, String> depRoots;

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
    this.depRoots = const {},
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

    final resolved = <String, String>{};
    for (final import in imports) {
      final importPath = _resolveImportPath(import.path, baseDir);
      resolved[import.path] = p.absolute(importPath);
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
      resolvedImports: resolved,
    );
  }

  /// Reject the alias mistakes that would otherwise surface as a silent
  /// wrong-value at runtime.
  ///
  /// Un alias est lié dans la portée du fichier qui l'écrit : deux paquets
  /// peuvent choisir le même nom sans jamais se voir. Les vérifications se
  /// font donc paquet par paquet — sauf les noms réservés, qui appartiennent
  /// à l'hôte partout.
  void _checkScopes() {
    for (final module in _modules.values) {
      // Un module DU PROJET importé des deux façons ne peut pas être émis :
      // avec un alias il devient une fermeture, et l'importateur à plat n'y
      // trouverait rien. Une dépendance, elle, est toujours une fermeture et
      // chaque importateur reçoit son propre lien : les deux formes
      // cohabitent sans se gêner.
      if (module.importedFlat &&
          module.isScoped &&
          _packageOf(module.path) == null) {
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
      }
    }

    // paquet -> (alias -> module qu'il désigne dans ce paquet)
    final ownersByPackage = <String?, Map<String, BundledModule>>{};
    for (final module in _modules.values) {
      final owners =
          ownersByPackage.putIfAbsent(_packageOf(module.path), () => {});
      for (final import in module.imports) {
        if (import.alias == null) continue;
        final target = _modules[module.resolvedImports[import.path]];
        if (target == null) continue;
        final owner = owners[import.alias!];
        if (owner != null && owner.path != target.path) {
          throw BundlerException(
            'Alias "${import.alias}" names two different modules: '
            '${_relative(owner.path)} and ${_relative(target.path)}.',
          );
        }
        owners[import.alias!] = target;
      }
    }

    // An alias belongs to the file that imported it. Rien n'empêcherait un
    // fichier de lire l'alias d'un voisin du même paquet — et ce code
    // casserait le jour où les modules deviennent réels.
    for (final module in _modules.values) {
      final owners = ownersByPackage[_packageOf(module.path)] ?? const {};
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

  /// Le paquet auquel appartient [absolutePath] : le nom de la dépendance qui
  /// le contient, ou null pour les fichiers du projet lui-même.
  String? _packageOf(String absolutePath) {
    for (final entry in depRoots.entries) {
      if (p.isWithin(entry.value, absolutePath)) return entry.key;
    }
    return null;
  }

  /// Write the collected modules out.
  ///
  /// Un module de dépendance est TOUJOURS enfermé dans sa fermeture, et ce
  /// qu'il importe lui est relié nommément, chez lui. Ses déclarations et ses
  /// alias internes n'existent donc que pour lui : le projet ne peut ni les
  /// lire, ni les écraser — et deux dépendances ne se voient pas davantage.
  ///
  /// Les fichiers du projet gardent l'émission historique (à plat, ou en
  /// fermeture quand ils sont importés `as`) : rien ne bouge pour un projet
  /// sans dépendances. Seuls leurs imports de dépendances sont reliés
  /// explicitement, là où ils sont écrits.
  void _emit() {
    for (final module in _modules.values) {
      final isDep = _packageOf(module.path) != null;
      _output.writeln('// === ${p.basename(module.path)} ===');
      _line++;

      final internal =
          isDep || module.isScoped ? _internalName(module.path) : null;
      if (internal != null) {
        _output.writeln('let $internal = fn() {');
        _line++;
      }

      // Un module du projet trouve les fichiers du projet à plat, là où ils
      // ont toujours été ; seules les dépendances demandent un lien.
      _emitBindings(module, depsOnly: !isDep);

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
        // Une dépendance ne pose aucun nom global : c'est l'importateur qui
        // lie l'alias chez lui, quand vient son tour.
        if (!isDep) {
          for (final alias in module.aliases) {
            _output.writeln('let $alias = $internal');
            _line++;
          }
        }
      }

      _output.writeln();
      _line++;
    }
  }

  /// Relie les imports de [module] dans sa propre portée : `as` pose l'alias,
  /// la forme à plat pose chaque export du module importé.
  ///
  /// [depsOnly] saute les fichiers du projet — ils sont déjà émis à plat, et
  /// les relier une seconde fois changerait la sémantique historique.
  void _emitBindings(BundledModule module, {required bool depsOnly}) {
    for (final import in module.imports) {
      final target = _modules[module.resolvedImports[import.path]];
      if (target == null) continue;
      if (depsOnly && _packageOf(target.path) == null) continue;

      final internal = _internalName(target.path);
      if (import.alias != null) {
        _output.writeln('let ${import.alias} = $internal');
        _line++;
        continue;
      }
      for (final name in target.surface.exports) {
        _output.writeln('let $name = $internal.$name');
        _line++;
      }
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

  /// Resolve import path relative to current file, or inside a declared
  /// dependency when the first segment names one.
  String _resolveImportPath(String importPath, String baseDir) {
    final dep = _resolveDepImport(importPath, baseDir);
    if (dep != null) return dep;

    var resolved = importPath;
    if (!resolved.endsWith('.ks')) {
      resolved = '$resolved.ks';
    }
    return p.normalize(p.join(baseDir, resolved));
  }

  /// The dependency file `@use [importPath]` designates, or null when the
  /// first segment is not a declared dependency. `@use "money"` alone means
  /// the dependency's `main.ks`. An explicit `./` prefix always stays local,
  /// and a bare `money.ks` does not match the dependency `money`.
  String? _resolveDepImport(String importPath, String baseDir) {
    if (depRoots.isEmpty) return null;
    if (importPath.startsWith('./') || importPath.startsWith('../')) {
      return null;
    }

    final slash = importPath.indexOf('/');
    final first = slash < 0 ? importPath : importPath.substring(0, slash);
    final root = depRoots[first];
    if (root == null) return null;

    final rest = slash < 0 ? '' : importPath.substring(slash + 1);
    var target = rest.isEmpty ? 'main.ks' : rest;
    if (!target.endsWith('.ks')) target = '$target.ks';

    final resolved = p.normalize(p.join(root, target));
    if (!p.isWithin(root, resolved)) {
      throw BundlerException(
          '@use "$importPath" escapes dependency "$first" — imports may not '
          'leave the dependency directory.');
    }

    // Un fichier local homonyme ne doit pas être masqué en silence.
    final local = importPath.endsWith('.ks') ? importPath : '$importPath.ks';
    if (File(p.normalize(p.join(baseDir, local))).existsSync()) {
      throw BundlerException(
          '@use "$importPath" is ambiguous: "$first" is a declared '
          'dependency, but the local file "$local" also exists next to the '
          'importer. Use "./$local" for the local file, or rename one of '
          'them.');
    }

    return resolved;
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
    'primary': '#6750A4',
    'onPrimary': '#FFFFFF',
    'primaryContainer': '#EADDFF',
    'onPrimaryContainer': '#21005D',
    'secondary': '#625B71',
    'onSecondary': '#FFFFFF',
    'secondaryContainer': '#E8DEF8',
    'onSecondaryContainer': '#1D192B',
    'tertiary': '#7D5260',
    'onTertiary': '#FFFFFF',
    'surface': '#FEF7FF',
    'onSurface': '#1D1B20',
    'onSurfaceVariant': '#49454F',
    'surfaceContainerLowest': '#FFFFFF',
    'surfaceContainerLow': '#F7F2FA',
    'surfaceContainer': '#F3EDF7',
    'surfaceContainerHigh': '#ECE6F0',
    'surfaceContainerHighest': '#E6E0E9',
    'inverseSurface': '#322F35',
    'onInverseSurface': '#F5EFF7',
    'inversePrimary': '#D0BCFF',
    'error': '#B3261E',
    'onError': '#FFFFFF',
    'errorContainer': '#F9DEDC',
    'onErrorContainer': '#410E0B',
    'outline': '#79747E',
    'outlineVariant': '#CAC4D0',
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
