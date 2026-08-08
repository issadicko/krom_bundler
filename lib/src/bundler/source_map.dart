import 'package:path/path.dart' as p;

/// Un fichier source et l'intervalle de lignes qu'il occupe dans le bundle.
class BundleSegment {
  BundleSegment({
    required this.path,
    required this.bundleStart,
    required this.lineCount,
  });

  /// Chemin absolu du fichier.
  final String path;

  /// Ligne du bundle (1-indexée) qui porte la première ligne du fichier.
  final int bundleStart;

  /// Nombre de lignes du fichier dans le bundle.
  final int lineCount;
}

/// Une position dans un fichier du projet.
class BundleLocation {
  BundleLocation({required this.path, required this.line});

  /// Chemin affichable — relatif à la racine du projet quand elle est connue.
  final String path;

  /// Ligne dans ce fichier, 1-indexée.
  final int line;

  @override
  String toString() => '$path:$line';
}

/// Où retomber, dans les fichiers d'origine, quand le moteur parle du bundle.
///
/// Le bundle est une concaténation : les `@use` (résolus transitivement,
/// dédupliqués) puis la page, chacun précédé d'une ligne d'en-tête. Une erreur
/// « at line 207 » désigne donc le bundle, pas le fichier ouvert dans
/// l'éditeur — ici la ligne 180 de `pages/home.ks`. Cette table refait le
/// chemin inverse, pour que les positions affichées soient cliquables.
class BundleSourceMap {
  BundleSourceMap(this.segments, {this.root});

  final List<BundleSegment> segments;

  /// Racine pour l'affichage des chemins. `null` garde les chemins absolus.
  final String? root;

  /// Toute position `at line L[:C]`, quel que soit le format du moteur :
  /// `SyntaxError: … at line 207:31`, `RuntimeError: … at line 207`,
  /// et le suffixe ` (at line 207:31)`.
  static final _position = RegExp(r'at line (\d+)(?::(\d+))?');

  /// Le fichier et la ligne d'origine de [bundleLine], ou `null` si elle tombe
  /// entre deux fichiers (ligne d'en-tête, séparateur) — auquel cas il n'y a
  /// rien de plus juste à dire que le numéro brut.
  BundleLocation? locate(int bundleLine) {
    for (final segment in segments) {
      final end = segment.bundleStart + segment.lineCount;
      if (bundleLine >= segment.bundleStart && bundleLine < end) {
        return BundleLocation(
          path: root == null ? segment.path : p.relative(segment.path, from: root),
          line: bundleLine - segment.bundleStart + 1,
        );
      }
    }
    return null;
  }

  /// [message] avec ses positions réécrites en `fichier:ligne:colonne`.
  ///
  /// [preludeLines] compte les lignes que l'appelant a ajoutées DEVANT le
  /// bundle — les stubs de validation, le prélude du moteur : elles décalent
  /// tout ce que le moteur annonce. Une position qu'on ne sait pas situer est
  /// laissée telle quelle : mieux vaut un numéro brut qu'un faux.
  String remap(String message, {int preludeLines = 0}) {
    return message.replaceAllMapped(_position, (match) {
      final line = int.parse(match[1]!) - preludeLines;
      final where = locate(line);
      if (where == null) return match[0]!;
      final column = match[2];
      return 'at ${where.path}:${where.line}${column == null ? '' : ':$column'}';
    });
  }
}

/// Le nombre de lignes qu'occupe [source] une fois écrit suivi d'un saut.
int countLines(String source) => '\n'.allMatches(source).length + 1;

extension BundleSourceMapJson on BundleSourceMap {
  /// La table sous la forme embarquée dans un manifeste de développement, que
  /// le SDK relit pour situer ses erreurs d'exécution.
  ///
  /// Clés courtes — `f`ichier, ligne de `d`épart, `n`ombre de lignes — parce
  /// qu'elle voyage dans le manifeste à chaque rebuild.
  List<Map<String, Object>> toJson() => [
        for (final segment in segments)
          {
            'f': root == null
                ? segment.path
                : p.relative(segment.path, from: root!),
            'd': segment.bundleStart,
            'n': segment.lineCount,
          }
      ];
}
