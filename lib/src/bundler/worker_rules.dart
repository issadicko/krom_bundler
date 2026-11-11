import 'package:krom_script/krom_script.dart';

import '../libs/known_libs.dart';
import 'module_scope.dart';
import 'source_map.dart';

/// Le seul namespace d'un worker, stubé pour la validation qui exécute le
/// premier niveau de son bundle.
const kWorkerPrelude = 'let worker = { progress: fn(value) { return null } }';

/// Les noms qu'une page tient de l'hôte et qu'un worker n'a pas.
///
/// Toutes les libs connues comptent, déclarées ou non : aucune n'est branchée
/// dans l'isolate d'un worker.
Set<String> namesMissingInWorkers({
  Iterable<String> customWidgets = const [],
}) =>
    {
      ...kHostGlobals.difference(const {'worker'}),
      ...KnownLibs.componentsFor(KnownLibs.packs),
      ...KnownLibs.moduleNamesFor(KnownLibs.packs),
      ...customWidgets,
    };

/// Ce que `worker.run` peut viser dans un worker : les noms posés au premier
/// niveau de son bundle, imports à plat compris.
class WorkerExports {
  WorkerExports._(this._names, this._functions);

  static final empty = WorkerExports._(const {}, const {});

  /// Tous les noms de premier niveau.
  final Set<String> _names;

  /// Ceux qui peuvent être une fonction. `let f = make()` en fait partie : sa
  /// valeur n'est connue qu'à l'exécution.
  final Set<String> _functions;

  factory WorkerExports.of(Program program) {
    final names = <String>{};
    final functions = <String>{};

    void bind(String name, Expression? value) {
      names.add(name);
      if (value == null || !_isData(value)) functions.add(name);
    }

    void visit(List<Statement> statements) {
      for (final statement in statements) {
        switch (statement) {
          case FunctionDeclaration():
            bind(statement.name.value, null);
          case VarDecl():
            bind(statement.name.value, statement.value);
          case ExpressionStatement(
              expression: Assignment(left: Identifier(:final value))
            ):
            bind(value, (statement.expression as Assignment).value);
          case IfStatement():
            visit(statement.consequence.statements);
            if (statement.alternative != null) {
              visit(statement.alternative!.statements);
            }
          case BlockStatement():
            visit(statement.statements);
          default:
            break;
        }
      }
    }

    visit(program.statements);
    return WorkerExports._(names, functions);
  }

  /// Vrai si la fonction [function] de `worker.run("<w>.<function>")` peut
  /// exister. Le runtime descend les maps d'une cible pointée
  /// (`fmt.money`) : seul son premier segment est vérifié ici.
  bool provides(String function) {
    final dot = function.indexOf('.');
    return dot < 0
        ? _functions.contains(function)
        : _names.contains(function.substring(0, dot));
  }

  static bool _isData(Expression value) =>
      value is NumberLiteral ||
      value is StringLiteral ||
      value is StringTemplate ||
      value is BooleanLiteral ||
      value is NullLiteral ||
      value is ArrayLiteral ||
      value is ObjectLiteral;
}

/// Les erreurs du bundle d'un worker : un nom que seule une page reçoit (R1),
/// ou un worker lancé depuis un worker (R2).
///
/// [program] est la concaténation brute, que [sourceMap] situe dans les
/// fichiers du projet.
List<String> checkWorkerBundle(
  Program program,
  BundleSourceMap? sourceMap, {
  required Set<String> missing,
}) {
  final reads = freeReads(program);
  final problems = <(Token, String)>[
    for (final name in reads.names)
      if (missing.contains(name.value))
        (
          name.token,
          '« ${name.value} » n\'existe pas dans un worker : seuls le langage '
              'et worker.progress y sont disponibles.'
        ),
    for (final use in reads.members)
      if (use.object.value == 'worker' &&
          (use.member.value == 'run' || use.member.value == 'cancel'))
        (
          use.object.token,
          'Un worker ne peut pas lancer d\'autre worker : seul '
              'worker.progress existe ici.'
        ),
  ];
  return _format(problems, sourceMap);
}

/// Les erreurs du bundle d'une page ou d'un composant : une cible littérale de
/// `worker.run` qui ne mène à rien (R3), ou `worker.progress` (R4).
List<String> checkPageBundle(
  Program program,
  BundleSourceMap? sourceMap, {
  required Map<String, WorkerExports> workers,
}) {
  final problems = <(Token, String)>[];
  for (final use in freeReads(program).members) {
    if (use.object.value != 'worker') continue;
    switch (use.member.value) {
      case 'progress':
        problems.add((
          use.object.token,
          'worker.progress n\'existe que dans un worker.',
        ));
      case 'run':
        final call = use.call;
        if (call == null || call.arguments.isEmpty) continue;
        final target = call.arguments.first;
        if (target is! StringLiteral) continue;
        final message = _targetProblem(target.value, workers);
        if (message != null) problems.add((target.token, message));
    }
  }
  return _format(problems, sourceMap);
}

String? _targetProblem(String target, Map<String, WorkerExports> workers) {
  // Même découpe que le runtime : au premier point.
  final dot = target.indexOf('.');
  if (dot <= 0) return 'worker.run attend "worker.fonction".';
  final name = target.substring(0, dot);
  final function = target.substring(dot + 1);
  final exports = workers[name];
  if (exports == null) {
    return 'Worker « $name » inconnu : déclarez-le dans manifest.json, sous '
        '"workers".';
  }
  if (!exports.provides(function)) {
    return 'Le worker « $name » n\'a pas de fonction « $function ».';
  }
  return null;
}

List<String> _format(List<(Token, String)> problems, BundleSourceMap? map) {
  problems.sort((a, b) {
    final line = a.$1.line.compareTo(b.$1.line);
    return line != 0 ? line : a.$1.column.compareTo(b.$1.column);
  });
  return [
    for (final (token, message) in problems)
      '${map?.locate(token.line) ?? 'line ${token.line}'}:${token.column}: '
          '$message',
  ];
}
