import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'bundler.dart';

/// Combien pèse la duplication des modules dans un build.
///
/// Chaque page est une unité autonome — le runtime lui donne son propre moteur,
/// sans rien partager — donc un module importé par trois pages est recopié
/// trois fois. Ce rapport dit ce que ça coûte réellement, une fois compressé,
/// pour qu'on décide d'un système de chunks partagés sur des chiffres plutôt
/// que sur une intuition.
class BundleStats {
  /// Chemin absolu du module -> unités (pages, composants) qui l'embarquent.
  final Map<String, Set<String>> _holders = {};

  /// Chemin absolu du module -> sa source nettoyée.
  final Map<String, String> _sources = {};

  /// Unité -> les modules qu'elle embarque, elle comprise.
  final Map<String, List<String>> _units = {};

  /// Scripts finaux, tels qu'ils partent dans le manifeste.
  final List<String> _scripts = [];

  final String? projectRoot;

  BundleStats({this.projectRoot});

  /// Enregistre ce que [unit] (une page ou un composant) a embarqué.
  void record(String unit, List<BundledModule> modules, String script) {
    _scripts.add(script);
    _units[unit] = modules.map((m) => m.path).toList();
    for (final module in modules) {
      _sources[module.path] = module.cleanedSource;
      // L'unité elle-même figure dans la liste, mais elle n'est embarquée
      // qu'une fois : elle n'entre pas dans le compte des doublons.
      if (module.path == p.absolute(unit)) continue;
      (_holders[module.path] ??= {}).add(unit);
    }
  }

  bool get isEmpty => _scripts.isEmpty;

  /// Les modules présents dans plus d'une unité, du plus coûteux au moins.
  List<({String path, int size, int copies, int wasted})> get duplicated {
    final rows = <({String path, int size, int copies, int wasted})>[];
    _holders.forEach((path, units) {
      if (units.length < 2) return;
      final size = _sources[path]?.length ?? 0;
      rows.add((
        path: path,
        size: size,
        copies: units.length,
        wasted: size * (units.length - 1),
      ));
    });
    rows.sort((a, b) => b.wasted.compareTo(a.wasted));
    return rows;
  }

  int get _rawTotal => _scripts.fold(0, (sum, s) => sum + s.length);

  int get _gzipTotal => _gzip(_scripts.join());

  /// Ce que pèse le transport actuel, mesuré sur les sources : chaque unité
  /// porte tous ses modules.
  String get _transportedNow => _units.values
      .expand((paths) => paths.map((path) => _sources[path] ?? ''))
      .join();

  /// Ce qu'il pèserait si chaque module n'était transporté qu'une fois.
  String get _transportedDeduplicated {
    final seen = <String>{};
    final buffer = StringBuffer();
    for (final paths in _units.values) {
      for (final path in paths) {
        if (seen.add(path)) buffer.write(_sources[path] ?? '');
      }
    }
    return buffer.toString();
  }

  static int _gzip(String text) => gzip.encode(utf8.encode(text)).length;

  String _relative(String path) => projectRoot == null
      ? p.basename(path)
      : p.relative(path, from: projectRoot!);

  static String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} KB';

  /// Le rapport, prêt à être imprimé.
  String report() {
    if (isEmpty) return '  Aucun script à analyser.';

    final rows = duplicated;
    final buffer = StringBuffer();
    buffer.writeln('  Duplication des modules');
    buffer.writeln('  ───────────────────────');

    if (rows.isEmpty) {
      buffer.writeln('    Aucun module partagé : rien à dédupliquer.');
    } else {
      final width = rows
          .map((r) => _relative(r.path).length)
          .fold(0, (a, b) => a > b ? a : b);
      for (final row in rows) {
        buffer.writeln('    ${_relative(row.path).padRight(width)}  '
            '${_kb(row.size).padLeft(8)}  × ${row.copies}  '
            '→ ${_kb(row.wasted).padLeft(8)} en trop');
      }
    }

    // Le gain se mesure sur les sources, avant optimisation : les deux côtés
    // partent alors de la même matière, ce qui n'est pas le cas si on compare
    // les scripts finaux à une reconstruction.
    final now = _gzip(_transportedNow);
    final deduped = _gzip(_transportedDeduplicated);
    final delta = now - deduped;
    final percent = now == 0 ? 0.0 : delta * 100 / now;

    buffer.writeln();
    buffer.writeln(
        '    Sortie         ${_kb(_rawTotal)} brut, ${_kb(_gzipTotal)} gzip');
    buffer.writeln('    Transporté     ${_kb(now)} gzip');
    buffer.writeln('    Dédupliqué     ${_kb(deduped)} gzip '
        '— ${_kb(delta)} de gain, ${percent.toStringAsFixed(1)} %');
    buffer.writeln();

    if (percent < 20 && delta < 20 * 1024) {
      buffer.writeln('    La compression absorbe déjà la redite. Des chunks');
      buffer.writeln('    partagés coûteraient un changement de format pour');
      buffer.writeln('    ce gain-là.');
    } else {
      buffer.writeln('    Seuil franchi : des chunks partagés commencent à');
      buffer.writeln('    valoir leur changement de format.');
    }
    buffer.writeln();
    buffer.writeln('    Le gain ne porte que sur le transport. Chaque page a');
    buffer.writeln('    son propre moteur : un module partagé sera de toute');
    buffer.writeln('    façon réévalué à chaque ouverture.');

    return buffer.toString();
  }
}
