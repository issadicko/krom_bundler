import 'package:krom_script/krom_script.dart';

/// One `@use` directive.
///
/// [alias] is null for the historical flat form, which drops the imported file's
/// declarations straight into the importing scope.
class KromImport {
  final String path;
  final String? alias;

  /// 1-indexed line of the directive in its own file, for error messages.
  final int line;

  const KromImport({required this.path, this.alias, required this.line});

  bool get isScoped => alias != null;

  @override
  String toString() => alias == null ? '@use "$path"' : '@use "$path" as $alias';
}

/// Les noms que le runtime injecte avant de charger le script. Un alias qui en
/// reprend un ferait disparaître le namespace de l'hôte pour tout le bundle.
const kHostGlobals = <String>{
  'args',
  'device',
  'nav',
  'request',
  'storage',
  'theme',
  'timer',
  'ui',
};

final _importPattern = RegExp(
  r'@use\s+"([^"]+)"(?:[^\S\n]+as[^\S\n]+([A-Za-z_][A-Za-z0-9_]*))?',
);

/// Every `@use` in [source], in order of appearance.
List<KromImport> parseImports(String source) {
  final imports = <KromImport>[];
  for (final match in _importPattern.allMatches(source)) {
    imports.add(KromImport(
      path: match.group(1)!,
      alias: match.group(2),
      line: '\n'.allMatches(source.substring(0, match.start)).length + 1,
    ));
  }
  return imports;
}

/// [source] without its `@use` directives, **keeping the lines**.
///
/// The directive is blanked rather than deleted so a file's own line numbers
/// survive into the bundle: without that, everything below an import would
/// already be off by one before the concatenation even starts.
String stripImports(String source) => source.replaceAll(_importPattern, '');

/// What a file declares at top level, and which free names it reads.
class ModuleSurface {
  /// Top-level `let` and `fn` names, in declaration order — what a scoped
  /// module hands back to its importers.
  final List<String> exports;

  /// Every identifier the file reads that it does not bind itself. Used to
  /// check that a file only reaches for aliases it imported.
  final Set<String> freeNames;

  const ModuleSurface({required this.exports, required this.freeNames});
}

/// Parse [source] and describe its surface.
///
/// Throws [ModuleParseException] on a syntax error; the caller turns that into
/// a message carrying the file name, which the parser alone cannot know.
ModuleSurface analyzeSource(String source) {
  final parser = Parser(Lexer(source));
  final program = parser.parseProgram();
  if (parser.errors().isNotEmpty) {
    throw ModuleParseException(parser.errors());
  }

  final exports = <String>[];
  for (final statement in program.statements) {
    switch (statement) {
      case VarDecl():
        exports.add(statement.name.value);
      case FunctionDeclaration():
        exports.add(statement.name.value);
      default:
        break;
    }
  }

  final collector = _FreeNameCollector()..program(program);
  return ModuleSurface(
    exports: exports,
    freeNames: collector.free,
  );
}

class ModuleParseException implements Exception {
  final List<String> errors;
  ModuleParseException(this.errors);
}

/// Collects the identifiers a program reads without binding them.
///
/// Scope tracking stays deliberately coarse — a name bound anywhere in an
/// enclosing block counts as bound. The result feeds a "did you import this
/// alias?" check, where a false negative merely lets a name through and the
/// engine still resolves it as it always did.
class _FreeNameCollector {
  final Set<String> free = {};
  final List<Set<String>> _scopes = [{}];

  void program(Program node) {
    // Top-level declarations are hoisted for this purpose: a file may call a
    // function it declares further down.
    for (final statement in node.statements) {
      switch (statement) {
        case VarDecl():
          _bind(statement.name.value);
        case FunctionDeclaration():
          _bind(statement.name.value);
        default:
          break;
      }
    }
    for (final statement in node.statements) {
      _statement(statement);
    }
  }

  void _bind(String name) => _scopes.last.add(name);

  bool _isBound(String name) => _scopes.any((scope) => scope.contains(name));

  void _push() => _scopes.add({});
  void _pop() => _scopes.removeLast();

  void _block(BlockStatement node) {
    _push();
    for (final statement in node.statements) {
      _statement(statement);
    }
    _pop();
  }

  void _statement(Statement? node) {
    switch (node) {
      case null:
        return;
      case VarDecl():
        _expression(node.value);
        _bind(node.name.value);
      case FunctionDeclaration():
        _bind(node.name.value);
        _push();
        for (final parameter in node.parameters) {
          _bind(parameter.value);
        }
        for (final statement in node.body.statements) {
          _statement(statement);
        }
        _pop();
      case ExpressionStatement():
        _expression(node.expression);
      case IfStatement():
        _expression(node.condition);
        _block(node.consequence);
        if (node.alternative != null) _block(node.alternative!);
      case BlockStatement():
        _block(node);
      case ReturnStatement():
        _expression(node.value);
      case ForStatement():
        _expression(node.iterable);
        _push();
        _bind(node.variable.value);
        for (final statement in node.body.statements) {
          _statement(statement);
        }
        _pop();
      case WhileStatement():
        _expression(node.condition);
        _block(node.body);
    }
  }

  void _expression(Expression? node) {
    switch (node) {
      case null:
        return;
      case Identifier():
        if (!_isBound(node.value)) free.add(node.value);
      case Assignment():
        _expression(node.left);
        _expression(node.value);
      case StringTemplate():
        node.parts.forEach(_expression);
      case ArrayLiteral():
        node.elements.forEach(_expression);
      case ObjectLiteral():
        // Keys are plain strings, never references.
        node.pairs.values.forEach(_expression);
      case IndexExpr():
        _expression(node.left);
        _expression(node.index);
      case BinaryExpr():
        _expression(node.left);
        _expression(node.right);
      case UnaryExpr():
        _expression(node.right);
      case TernaryExpr():
        _expression(node.condition);
        _expression(node.consequent);
        _expression(node.alternate);
      case ElvisExpr():
        _expression(node.left);
        _expression(node.defaultValue);
      // The property side of `a.b` is a member name, not a variable.
      case PropertyAccessExpr():
        _expression(node.obj);
      case SafeAccessExpr():
        _expression(node.obj);
      case FunctionLiteral():
        _push();
        for (final parameter in node.parameters) {
          _bind(parameter.value);
        }
        for (final statement in node.body.statements) {
          _statement(statement);
        }
        _pop();
      case CallExpr():
        _expression(node.function);
        node.arguments.forEach(_expression);
      default:
        break;
    }
  }
}
