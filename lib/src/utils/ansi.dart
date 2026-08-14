import 'dart:io';

/// La palette ANSI, en un seul endroit.
///
/// Le logger et les questions interactives écrivent tous deux sur le terminal ;
/// deux tables de codes finiraient par diverger — et un écart de couleur ne se
/// voit pas en revue, seulement à l'exécution.
class Ansi {
  static const reset = '\x1B[0m';
  static const bold = '\x1B[1m';
  static const dim = '\x1B[2m';
  static const red = '\x1B[31m';
  static const green = '\x1B[32m';
  static const yellow = '\x1B[33m';
  static const blue = '\x1B[34m';
  static const magenta = '\x1B[35m';
  static const cyan = '\x1B[36m';
  static const white = '\x1B[37m';
  static const gray = '\x1B[90m';

  /// Le vert-sarcelle de l'accent Krom (`#1d9e75` dans le guide), en 256
  /// couleurs — le seul mode que tous les terminaux modernes rendent pareil.
  static const accent = '\x1B[38;5;36m';

  // --- Mouvements de curseur, pour redessiner une question en place ---

  static String up(int lines) => '\x1B[${lines}A';
  static const clearLine = '\x1B[2K';
  static const hideCursor = '\x1B[?25l';
  static const showCursor = '\x1B[?25h';

  /// Vrai quand la sortie va vers un terminal qui accepte la couleur.
  ///
  /// `hasTerminal` seul ne suffit pas : `NO_COLOR` est la convention que
  /// respectent les CI et les utilisateurs qui n'en veulent pas, et `TERM=dumb`
  /// annonce un terminal qui n'interprète aucune séquence — dans les deux cas,
  /// écrire des codes ANSI revient à polluer la sortie de caractères parasites.
  static bool enabled = stdout.hasTerminal &&
      !Platform.environment.containsKey('NO_COLOR') &&
      Platform.environment['TERM'] != 'dumb';

  static String paint(String color, String text) =>
      enabled ? '$color$text$reset' : text;
}
