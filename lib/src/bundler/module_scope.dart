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
  String toString() =>
      alias == null ? '@use "$path"' : '@use "$path" as $alias';
}

/// Les noms que le runtime injecte avant de charger le script. Un alias qui en
/// reprend un ferait disparaître le namespace de l'hôte pour tout le bundle.
const kHostGlobals = <String>{
  'args',
  'clipboard',
  'device',
  'nav',
  'request',
  'storage',
  'theme',
  'timer',
  'ui',
  'worker',
};

final _importPattern = RegExp(
  r'@use\s+"([^"]+)"(?:[^\S\n]+as[^\S\n]+([A-Za-z_][A-Za-z0-9_]*))?',
);

/// [source] avec ses commentaires (`//`, `/* */`) blanchis, longueur et sauts
/// de ligne préservés — un `@use` écrit dans un commentaire est de la
/// documentation, pas une directive. Les chaînes restent intactes (les
/// chemins d'import en sont), mais leur état est suivi : un `//` dans une
/// chaîne n'ouvre pas de commentaire.
String maskComments(String source) {
  final out = source.codeUnits.toList();
  const space = 0x20;
  const newline = 0x0A;
  var inString = false;
  var stringChar = 0;
  var inLine = false;
  var inBlock = false;

  void blank(int i) {
    if (i < out.length && out[i] != newline) out[i] = space;
  }

  for (var i = 0; i < source.length; i++) {
    final c = source.codeUnitAt(i);
    if (inLine) {
      if (c == newline) {
        inLine = false;
      } else {
        blank(i);
      }
      continue;
    }
    if (inBlock) {
      if (c == 0x2A /* * */ &&
          i + 1 < source.length &&
          source.codeUnitAt(i + 1) == 0x2F /* / */) {
        blank(i);
        blank(i + 1);
        i++;
        inBlock = false;
      } else {
        blank(i);
      }
      continue;
    }
    if (inString) {
      // L'échappement se consomme en avançant — regarder en arrière se fait
      // piéger par un antislash lui-même échappé.
      if (c == 0x5C /* \ */) {
        i++;
        continue;
      }
      if (c == stringChar) inString = false;
      continue;
    }
    if (c == 0x2F /* / */ && i + 1 < source.length) {
      final next = source.codeUnitAt(i + 1);
      if (next == 0x2F) {
        inLine = true;
        blank(i);
        continue;
      }
      if (next == 0x2A /* * */) {
        inBlock = true;
        blank(i);
        continue;
      }
    }
    if (c == 0x22 /* " */ || c == 0x27 /* ' */) {
      inString = true;
      stringChar = c;
    }
  }
  return String.fromCharCodes(out);
}

/// Every `@use` in [source], in order of appearance — comments masked first.
List<KromImport> parseImports(String source) {
  final masked = maskComments(source);
  final imports = <KromImport>[];
  for (final match in _importPattern.allMatches(masked)) {
    imports.add(KromImport(
      path: match.group(1)!,
      alias: match.group(2),
      line: '\n'.allMatches(masked.substring(0, match.start)).length + 1,
    ));
  }
  return imports;
}

/// [source] without its `@use` directives, **keeping the lines**.
///
/// The directive is blanked rather than deleted so a file's own line numbers
/// survive into the bundle: without that, everything below an import would
/// already be off by one before the concatenation even starts. Les directives
/// sont repérées sur le texte masqué : celles des commentaires restent.
String stripImports(String source) {
  final masked = maskComments(source);
  final buffer = StringBuffer();
  var last = 0;
  for (final match in _importPattern.allMatches(masked)) {
    buffer.write(source.substring(last, match.start));
    last = match.end;
  }
  buffer.write(source.substring(last));
  return buffer.toString();
}

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

  final reads = freeReads(program);
  return ModuleSurface(
    exports: exports,
    freeNames: {for (final name in reads.names) name.value},
  );
}

class ModuleParseException implements Exception {
  final List<String> errors;
  ModuleParseException(this.errors);
}

/// `objet.membre` lu sur un nom que le programme ne lie pas — un namespace de
/// l'hôte, le plus souvent.
class FreeMember {
  const FreeMember(this.object, this.member, this.call);

  final Identifier object;
  final Identifier member;

  /// L'appel dont cet accès est la fonction (`worker.run(…)`), ou null pour
  /// une simple lecture.
  final CallExpr? call;
}

/// Ce qu'un programme lit sans le lier lui-même, dans l'ordre du source.
class FreeReads {
  const FreeReads({required this.names, required this.members});

  /// Chaque occurrence d'un identifiant libre, avec sa position.
  final List<Identifier> names;

  /// Chaque accès `nom.membre` dont le `nom` est libre.
  final List<FreeMember> members;
}

/// Les lectures libres de [program].
FreeReads freeReads(Program program) {
  final collector = _FreeNameCollector()..program(program);
  return FreeReads(names: collector.names, members: collector.members);
}

/// Collects the identifiers a program reads without binding them.
///
/// KromScript n'ouvre de portée qu'à l'appel d'une fonction : un `let` écrit
/// dans un `if` ou une boucle vaut pour toute la fonction. Un nom lié n'importe
/// où dans une fonction englobante compte donc comme lié, même lu avant sa
/// déclaration. L'approximation penche du côté sûr : un nom laissé passer à
/// tort est résolu par le moteur comme il l'a toujours été.
class _FreeNameCollector {
  final List<Identifier> names = [];
  final List<FreeMember> members = [];
  final List<Set<String>> _scopes = [];

  void program(Program node) {
    _enterFunction(const [], node.statements);
    _statements(node.statements);
    _scopes.removeLast();
  }

  bool _isBound(String name) => _scopes.any((scope) => scope.contains(name));

  void _enterFunction(List<Identifier> parameters, List<Statement> body) {
    final scope = {for (final parameter in parameters) parameter.value};
    _declare(body, scope);
    _scopes.add(scope);
  }

  /// Les noms que [statements] lient dans la fonction qui les contient, sans
  /// descendre dans les fonctions imbriquées. Une affectation à un nom inconnu
  /// le crée dans la fonction courante, comme un `let`.
  void _declare(List<Statement> statements, Set<String> into) {
    for (final statement in statements) {
      switch (statement) {
        case VarDecl():
          into.add(statement.name.value);
        case FunctionDeclaration():
          into.add(statement.name.value);
        case ExpressionStatement(
            expression: Assignment(left: Identifier(:final value))
          ):
          into.add(value);
        case IfStatement():
          _declare(statement.consequence.statements, into);
          if (statement.alternative != null) {
            _declare(statement.alternative!.statements, into);
          }
        case BlockStatement():
          _declare(statement.statements, into);
        case ForStatement():
          into.add(statement.variable.value);
          _declare(statement.body.statements, into);
        case WhileStatement():
          _declare(statement.body.statements, into);
        default:
          break;
      }
    }
  }

  void _statements(List<Statement> statements) {
    for (final statement in statements) {
      _statement(statement);
    }
  }

  void _function(List<Identifier> parameters, BlockStatement body) {
    _enterFunction(parameters, body.statements);
    _statements(body.statements);
    _scopes.removeLast();
  }

  void _statement(Statement? node) {
    switch (node) {
      case null:
        return;
      case VarDecl():
        _expression(node.value);
      case FunctionDeclaration():
        _function(node.parameters, node.body);
      case ExpressionStatement():
        _expression(node.expression);
      case IfStatement():
        _expression(node.condition);
        _statements(node.consequence.statements);
        if (node.alternative != null) {
          _statements(node.alternative!.statements);
        }
      case BlockStatement():
        _statements(node.statements);
      case ReturnStatement():
        _expression(node.value);
      case ForStatement():
        _expression(node.iterable);
        _statements(node.body.statements);
      case WhileStatement():
        _expression(node.condition);
        _statements(node.body.statements);
    }
  }

  void _member(Expression object, Identifier member, CallExpr? call) {
    if (object is Identifier && !_isBound(object.value)) {
      members.add(FreeMember(object, member, call));
    }
    _expression(object);
  }

  void _expression(Expression? node) {
    switch (node) {
      case null:
        return;
      case Identifier():
        if (!_isBound(node.value)) names.add(node);
      case Assignment():
        // `x = …` écrit x, il ne le lit pas.
        if (node.left is! Identifier) _expression(node.left);
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
        _member(node.obj, node.property, null);
      case SafeAccessExpr():
        _member(node.obj, node.property, null);
      case FunctionLiteral():
        _function(node.parameters, node.body);
      case CallExpr():
        switch (node.function) {
          case PropertyAccessExpr(:final obj, :final property):
            _member(obj, property, node);
          case SafeAccessExpr(:final obj, :final property):
            _member(obj, property, node);
          default:
            _expression(node.function);
        }
        node.arguments.forEach(_expression);
      default:
        break;
    }
  }
}
