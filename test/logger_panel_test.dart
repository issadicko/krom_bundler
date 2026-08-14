import 'dart:io';

import 'package:krom_bundler/src/utils/logger.dart';
import 'package:test/test.dart';

/// Un encadré dont la bordure ne ferme pas se voit tout de suite, mais seulement
/// sur le terminal de celui qui l'exécute — jamais dans une revue de code. La
/// géométrie est de l'arithmétique pure : autant la tenir ici.

/// Capture ce que [action] écrit sur stdout, couleurs désactivées.
List<String> _capture(void Function() action) {
  final lines = <String>[];
  Logger.useColorForTests = false;
  IOOverrides.runZoned(
    action,
    stdout: () => _CollectingStdout(lines),
  );
  return lines;
}

void main() {
  test('toutes les lignes de l\'encadré ont la même largeur', () {
    final lines = _capture(() => Logger.panel(
          'Krom Dev Server',
          [
            ('URL', 'http://192.168.1.24:4321'),
            ('Manifest', 'manifest.json'),
            ('Hot reload', 'enabled'),
          ],
          highlight: 'URL',
          footer: 'Watching for changes… Ctrl+C to stop.',
        )).where((l) => l.trim().isNotEmpty).toList();

    expect(lines, hasLength(6)); // haut + 3 lignes + pied + bas
    final widths = lines.map((l) => l.trimRight().length).toSet();
    expect(widths, hasLength(1), reason: 'lignes de largeurs différentes : $lines');
  });

  test('le cadre est fermé, et le pied tient dedans', () {
    final lines = _capture(() => Logger.panel(
          'Build',
          [('Duration', '412ms'), ('Pages', '3')],
          footer: 'un pied volontairement plus long que le contenu',
        )).where((l) => l.trim().isNotEmpty).toList();

    expect(lines.first.trim(), startsWith('╭─ Build ─'));
    expect(lines.first.trim(), endsWith('╮'));
    expect(lines.last.trim(), startsWith('╰─'));
    expect(lines.last.trim(), endsWith('╯'));
    for (final line in lines.sublist(1, lines.length - 1)) {
      expect(line.trim(), startsWith('│'));
      expect(line.trim(), endsWith('│'));
    }
  });

  test('un titre plus long que le contenu élargit le cadre', () {
    final lines = _capture(() => Logger.panel(
          'Un titre nettement plus long que ses lignes',
          [('a', 'b')],
        )).where((l) => l.trim().isNotEmpty).toList();

    final widths = lines.map((l) => l.trimRight().length).toSet();
    expect(widths, hasLength(1), reason: 'le titre déborde du cadre : $lines');
  });

  test('sans ligne, rien ne sort', () {
    expect(_capture(() => Logger.panel('Vide', const [])), isEmpty);
  });
}

/// Un stdout qui garde ses lignes au lieu de les écrire.
class _CollectingStdout implements Stdout {
  _CollectingStdout(this.lines);

  final List<String> lines;

  @override
  void writeln([Object? object = '']) => lines.add('$object');

  @override
  bool get hasTerminal => false;

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
