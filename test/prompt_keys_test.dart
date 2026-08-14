import 'package:krom_bundler/src/utils/keys.dart';
import 'package:test/test.dart';

/// Le décodage des touches et le déplacement dans une liste ne se vérifient pas
/// en pilotant un vrai terminal — et c'est précisément là que se logent les
/// décalages d'un cran, qui ne se voient que sous les doigts de quelqu'un.

/// Fait avaler [bytes] au lecteur et rend les actions complètes.
List<KeyAction> _actions(KeyReader reader, List<int> bytes) =>
    [for (final b in bytes) reader.feed(b)].whereType<KeyAction>().toList();

/// La séquence des trois octets d'une flèche.
List<int> _arrow(String letter) => [0x1B, 0x5B, letter.codeUnitAt(0)];

void main() {
  group('KeyReader', () {
    test('une flèche ne rend son action qu\'au troisième octet', () {
      final reader = KeyReader();
      expect(reader.feed(0x1B), isNull);
      expect(reader.feed(0x5B), isNull);
      expect(reader.feed(0x41), KeyAction.up);
    });

    test('haut et bas, flèches ou j/k', () {
      expect(_actions(KeyReader(), _arrow('A')), [KeyAction.up]);
      expect(_actions(KeyReader(), _arrow('B')), [KeyAction.down]);
      expect(_actions(KeyReader(), [0x6B]), [KeyAction.up]);
      expect(_actions(KeyReader(), [0x6A]), [KeyAction.down]);
    });

    test('entrée valide, Ctrl+C abandonne', () {
      expect(_actions(KeyReader(), [0x0A]), [KeyAction.accept]);
      expect(_actions(KeyReader(), [0x0D]), [KeyAction.accept]);
      expect(_actions(KeyReader(), [0x03]), [KeyAction.abort]);
    });

    test('un Échap seul n\'avale pas la frappe suivante', () {
      // La version naïve lisait deux octets de plus dès qu'elle voyait un ESC :
      // l'entrée qui suivait était consommée sans être interprétée, et la
      // question restait ouverte sans raison visible.
      final reader = KeyReader();
      expect(reader.feed(0x1B), isNull);
      expect(reader.feed(0x0A), KeyAction.accept);
    });

    test('un chiffre porte sa cible, base zéro', () {
      final reader = KeyReader();
      expect(reader.feed(0x31), KeyAction.jump); // '1'
      expect(reader.jumpTarget, 0);
      expect(reader.feed(0x34), KeyAction.jump); // '4'
      expect(reader.jumpTarget, 3);
    });

    test('le reste est ignoré, sans casser la séquence suivante', () {
      final reader = KeyReader();
      expect(reader.feed(0x7A), KeyAction.ignore); // z
      expect(_actions(reader, _arrow('B')), [KeyAction.down]);
    });
  });

  group('SelectCursor', () {
    test('les extrémités bouclent', () {
      final cursor = SelectCursor(3);
      cursor.up();
      expect(cursor.index, 2, reason: 'du premier vers le dernier');
      cursor.down();
      expect(cursor.index, 0, reason: 'du dernier vers le premier');
    });

    test('la position de départ est celle demandée, bornée', () {
      expect(SelectCursor(6, initial: 3).index, 3);
      expect(SelectCursor(6, initial: 99).index, 5);
      expect(SelectCursor(6, initial: -1).index, 0);
    });

    test('un raccourci hors liste ne bouge rien', () {
      final cursor = SelectCursor(6, initial: 2);
      cursor.jumpTo(8);
      expect(cursor.index, 2);
      cursor.jumpTo(-1);
      expect(cursor.index, 2);
      cursor.jumpTo(5);
      expect(cursor.index, 5);
    });
  });

  test('bout en bout : deux flèches vers le bas et entrée', () {
    final reader = KeyReader();
    final cursor = SelectCursor(6);
    var accepted = false;

    for (final byte in [..._arrow('B'), ..._arrow('B'), 0x0A]) {
      switch (reader.feed(byte)) {
        case KeyAction.down:
          cursor.down();
        case KeyAction.up:
          cursor.up();
        case KeyAction.accept:
          accepted = true;
        case _:
          break;
      }
    }

    expect(accepted, isTrue);
    expect(cursor.index, 2);
  });
}
