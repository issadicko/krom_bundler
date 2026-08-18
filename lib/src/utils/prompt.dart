import 'dart:io';

import 'ansi.dart';
import 'keys.dart';

/// Les questions que la CLI pose quand on ne lui a rien dit.
///
/// Le contrat, dans cet ordre : **un argument explicite gagne toujours** — on
/// ne demande que ce qui manque ; et **rien n'est demandé hors d'un terminal**.
/// Une CLI qui bloque sur une question dans un script CI ne se voit qu'au
/// timeout du job, vingt minutes plus tard, sans une ligne pour l'expliquer.
///
/// Le mode brut est posé et retiré autour de chaque lecture. Il l'est dans un
/// `finally` : sortir en laissant l'écho coupé rend le shell de l'utilisateur
/// inutilisable, et il n'a aucun moyen de deviner que c'est nous.
class Prompt {
  /// Vrai quand on peut poser une question : les deux bouts sont un terminal.
  ///
  /// `stdin` seul ne suffit pas — la sortie redirigée dans un fichier
  /// n'afficherait pas la question qu'on attend pourtant de voir répondue.
  static bool get isInteractive =>
      stdin.hasTerminal && stdout.hasTerminal && Ansi.enabled;

  static const _ctrlC = 3;
  static const _enter = 10;
  static const _return = 13;

  /// Une réponse acquise, dans la forme que Stac a rendue familière.
  static void _echo(String question, String answer) {
    stdout.writeln('  ${Ansi.paint(Ansi.green, '✓')} $question '
        '${Ansi.paint(Ansi.dim, '·')} ${Ansi.paint(Ansi.accent, answer)}');
  }

  /// Rend le terminal à son état d'origine, puis rend la main au shell.
  ///
  /// Ctrl+C pendant une question n'est pas une réponse : on ne devine pas, on
  /// sort. 130 est le code que tout shell attend d'un SIGINT.
  static Never _abort() {
    stdout.write(Ansi.showCursor);
    stdout.writeln();
    exit(130);
  }

  /// Exécute [body] en mode brut, et rétablit le terminal quoi qu'il arrive.
  static T _raw<T>(T Function() body) {
    final echo = stdin.echoMode;
    final line = stdin.lineMode;
    try {
      stdin.echoMode = false;
      stdin.lineMode = false;
      return body();
    } finally {
      stdin.lineMode = line;
      stdin.echoMode = echo;
      stdout.write(Ansi.showCursor);
    }
  }

  /// Une saisie libre. [validate] rend un message d'erreur, ou null si la
  /// valeur convient — la question est reposée tant qu'elle ne convient pas.
  static String text(
    String question, {
    String? placeholder,
    String? Function(String)? validate,
  }) {
    while (true) {
      final hint = placeholder == null
          ? ''
          : ' ${Ansi.paint(Ansi.dim, '($placeholder)')}';
      stdout.write('  ${Ansi.paint(Ansi.cyan, '?')} $question$hint '
          '${Ansi.paint(Ansi.dim, '›')} ');
      final answer = (stdin.readLineSync() ?? '').trim();

      final problem = validate?.call(answer);
      if (problem != null) {
        stdout.writeln('  ${Ansi.paint(Ansi.red, '✗')} $problem');
        continue;
      }

      // La ligne saisie est déjà à l'écran, écho du terminal compris : on la
      // remplace par la forme validée, pour que la trace soit homogène.
      stdout.write('${Ansi.up(1)}${Ansi.clearLine}');
      _echo(question, answer);
      return answer;
    }
  }

  /// Un choix dans une liste, aux flèches. [choices] porte la valeur rendue,
  /// son libellé et, en gris, ce à quoi elle sert.
  static T select<T>(
    String question,
    List<PromptChoice<T>> choices, {
    T? initial,
  }) {
    if (choices.isEmpty) {
      throw ArgumentError('select() sans choix');
    }
    final start =
        initial == null ? 0 : choices.indexWhere((c) => c.value == initial);
    final cursor = SelectCursor(choices.length, initial: start < 0 ? 0 : start);
    final reader = KeyReader();

    final labelWidth =
        choices.map((c) => c.label.length).reduce((a, b) => a > b ? a : b);

    return _raw(() {
      stdout.write(Ansi.hideCursor);
      var drawn = false;

      loop:
      while (true) {
        if (drawn) {
          // Remonter sur la question et tout réécrire : redessiner en place
          // évite de dérouler une page entière à chaque flèche.
          stdout.write(Ansi.up(choices.length + 1));
        }
        stdout.writeln(
            '${Ansi.clearLine}  ${Ansi.paint(Ansi.cyan, '?')} $question '
            '${Ansi.paint(Ansi.dim, '(↑↓ pour choisir, entrée pour valider)')}');
        for (var i = 0; i < choices.length; i++) {
          final choice = choices[i];
          final selected = i == cursor.index;
          final marker = selected ? Ansi.paint(Ansi.accent, '❯') : ' ';
          final label = selected
              ? Ansi.paint('${Ansi.bold}${Ansi.accent}',
                  choice.label.padRight(labelWidth))
              : choice.label.padRight(labelWidth);
          final description = choice.description == null
              ? ''
              : '  ${Ansi.paint(Ansi.dim, _fit(choice.description!, labelWidth))}';
          stdout.writeln('${Ansi.clearLine}  $marker $label$description');
        }
        drawn = true;

        // Une séquence incomplète (le `ESC` d'une flèche) rend null : on
        // redemande un octet sans redessiner, sinon la liste clignote.
        while (true) {
          final action = reader.feed(stdin.readByteSync());
          if (action == null) continue;
          switch (action) {
            case KeyAction.abort:
              _abort();
            case KeyAction.accept:
              break loop;
            case KeyAction.up:
              cursor.up();
            case KeyAction.down:
              cursor.down();
            case KeyAction.jump:
              cursor.jumpTo(reader.jumpTarget);
            case KeyAction.ignore:
              continue;
          }
          break;
        }
      }

      // Effacer la question et sa liste, ne garder que la réponse.
      stdout.write(Ansi.up(choices.length + 1));
      for (var i = 0; i <= choices.length; i++) {
        stdout.write('${Ansi.clearLine}\n');
      }
      stdout.write(Ansi.up(choices.length + 1));
      _echo(question, choices[cursor.index].label);
      return choices[cursor.index].value;
    });
  }

  /// Une question fermée. Entrée seule prend [initial].
  static bool confirm(String question, {bool initial = true}) {
    final suffix = initial ? 'O/n' : 'o/N';
    return _raw(() {
      while (true) {
        stdout.write('  ${Ansi.paint(Ansi.cyan, '?')} $question '
            '${Ansi.paint(Ansi.dim, '($suffix)')} ');
        final key = stdin.readByteSync();
        if (key == _ctrlC) _abort();

        final bool? answer = switch (key) {
          _enter || _return => initial,
          0x6F || 0x4F || 0x79 || 0x59 => true, // o O y Y
          0x6E || 0x4E => false, // n N
          _ => null,
        };
        stdout.write('\r${Ansi.clearLine}');
        if (answer == null) continue;
        _echo(question, answer ? 'oui' : 'non');
        return answer;
      }
    });
  }

  /// Tronque [text] pour que la ligne tienne dans le terminal.
  static String _fit(String text, int labelWidth) {
    final columns = stdout.hasTerminal ? stdout.terminalColumns : 80;
    final room = columns - labelWidth - 8;
    if (room <= 3 || text.length <= room) return text;
    return '${text.substring(0, room - 1)}…';
  }
}

/// Une option de [Prompt.select] : ce qu'on rend, ce qu'on lit, ce que ça fait.
class PromptChoice<T> {
  const PromptChoice(this.value, this.label, {this.description});

  final T value;
  final String label;
  final String? description;
}
