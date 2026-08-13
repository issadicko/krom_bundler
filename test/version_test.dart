import 'dart:io';

import 'package:test/test.dart';

/// La version vit à deux endroits : `pubspec.yaml`, qui pilote le paquet, et
/// `kromVersion` dans `bin/krom_bundler.dart`, qui est ce que `krom --version`
/// affiche. Rien ne les liait.
///
/// Les releases 0.3.16 et 0.3.17 sont parties avec la constante restée à
/// 0.3.15 : le binaire était le bon, mais il annonçait une version d'avant, ce
/// qui donne exactement l'impression que l'installation a échoué.
void main() {
  test('kromVersion suit la version du pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final declared = RegExp(r'^version:\s*(\S+)', multiLine: true)
        .firstMatch(pubspec)
        ?.group(1);
    expect(declared, isNotNull, reason: 'pubspec.yaml sans version');

    final main = File('bin/krom_bundler.dart').readAsStringSync();
    final constant = RegExp(r"const String kromVersion = '([^']+)'")
        .firstMatch(main)
        ?.group(1);
    expect(constant, isNotNull, reason: 'kromVersion introuvable');

    expect(
      constant,
      declared,
      reason: 'bin/krom_bundler.dart annonce $constant alors que le paquet '
          'est en $declared — `krom --version` mentirait sur la release.',
    );
  });
}
