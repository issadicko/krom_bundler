/// Ce qu'une touche demande, une fois sa séquence décodée.
enum KeyAction { up, down, accept, abort, jump, ignore }

/// Le décodage des touches, séparé de la lecture du terminal.
///
/// Une flèche arrive en trois octets (`ESC` `[` `A`), pas en un. La version
/// naïve lit les deux suivants dès qu'elle voit un `ESC` — et un Échap tapé
/// seul avale alors les deux frappes d'après, qui ne sont jamais interprétées.
/// En alimentant octet par octet, une séquence incomplète se referme sans rien
/// consommer de ce qui n'en fait pas partie.
///
/// Séparé aussi pour être testable : la logique d'une liste de choix — ce qui
/// remonte, ce qui redescend, ce qui boucle — ne se vérifie pas en pilotant un
/// vrai terminal, et c'est là que se logent les décalages d'un cran.
class KeyReader {
  _State _state = _State.plain;

  /// L'index visé par un raccourci chiffré, valide juste après un [KeyAction.jump].
  int jumpTarget = -1;

  /// Rend l'action quand la séquence est complète, `null` tant qu'elle ne l'est
  /// pas — l'appelant redemande alors un octet sans rien redessiner.
  KeyAction? feed(int byte) {
    switch (_state) {
      case _State.plain:
        if (byte == 0x1B) {
          _state = _State.escape;
          return null;
        }
        return _plain(byte);

      case _State.escape:
        if (byte == 0x5B) {
          _state = _State.bracket;
          return null;
        }
        // Échap suivi d'autre chose : la séquence n'en était pas une, et
        // l'octet courant garde son sens propre.
        _state = _State.plain;
        return _plain(byte);

      case _State.bracket:
        _state = _State.plain;
        return switch (byte) {
          0x41 => KeyAction.up, // A
          0x42 => KeyAction.down, // B
          _ => KeyAction.ignore,
        };
    }
  }

  KeyAction _plain(int byte) {
    if (byte == 0x03) return KeyAction.abort; // Ctrl+C
    if (byte == 0x0A || byte == 0x0D) return KeyAction.accept;
    if (byte == 0x6B) return KeyAction.up; // k, pour les doigts vim
    if (byte == 0x6A) return KeyAction.down; // j
    if (byte >= 0x31 && byte <= 0x39) {
      jumpTarget = byte - 0x31; // 1 -> index 0
      return KeyAction.jump;
    }
    return KeyAction.ignore;
  }
}

enum _State { plain, escape, bracket }

/// L'index courant d'une liste de choix, et ce que les touches en font.
///
/// Les extrémités bouclent : arrivé en bas, une flèche vers le bas revient en
/// tête. Sur six gabarits, remonter de cinq crans pour atteindre le dernier est
/// exactement ce qu'on ne veut pas faire.
class SelectCursor {
  SelectCursor(this.length, {int initial = 0})
      : assert(length > 0),
        index = initial.clamp(0, length - 1);

  final int length;
  int index;

  void up() => index = (index - 1 + length) % length;
  void down() => index = (index + 1) % length;

  /// Un raccourci chiffré hors liste ne bouge rien — mieux vaut ignorer un 8
  /// tapé sur six entrées que sauter à la dernière comme si c'était voulu.
  void jumpTo(int target) {
    if (target >= 0 && target < length) index = target;
  }
}
