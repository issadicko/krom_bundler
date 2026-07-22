import 'package:test/test.dart';
import 'package:krom_bundler/src/bundler/bundler.dart';
import 'package:krom_bundler/src/libs/known_libs.dart';

void main() {
  group('descripteurs embarqués', () {
    test('les trois packs de domaine sont connus du binaire', () {
      expect(KnownLibs.packs, containsAll(['charts', 'media', 'forms']));
    });

    test('un composant est rattaché à son pack', () {
      expect(KnownLibs.packOfComponent('LineChart'), 'charts');
      expect(KnownLibs.packOfComponent('MediaGrid'), 'media');
      expect(KnownLibs.packOfComponent('SignaturePad'), 'forms');
      expect(KnownLibs.packOfComponent('Text'), isNull); // widget du core
    });

    test('un module est rattaché à son pack', () {
      expect(KnownLibs.packOfModule('charts'), 'charts');
      expect(KnownLibs.packOfModule('media'), 'media');
      expect(KnownLibs.packOfModule('storage'), isNull); // natif du core
    });

    test('déclarer un pack apporte tous ses composants', () {
      final components = KnownLibs.componentsFor(['charts']);
      expect(components, hasLength(7));
      expect(components, contains('DonutChart'));
      expect(components, isNot(contains('MediaGrid')));
    });

    test('un pack inconnu est ignoré sans lever', () {
      expect(KnownLibs.componentsFor(['inexistant']), isEmpty);
      expect(KnownLibs.moduleStubFor(['inexistant']), isEmpty);
    });
  });

  group('validation avec les libs connues', () {
    test('un composant de lib valide dès que son pack est déclaré', () async {
      final bundler = Bundler();
      await bundler.validate(
        'fn build() { return LineChart({ data: [1, 2, 3] }) }',
        customWidgets: KnownLibs.componentsFor(['charts']),
      );
    });

    test('un appel de module à la racine valide — ce n\'était jamais une vraie '
        'limite, seulement un angle mort du bundler', () async {
      final bundler = Bundler();
      await bundler.validate(
        'let couleurs = charts.palette(5)\n'
        'fn build() { return DonutChart({ data: [1], colors: couleurs }) }',
        customWidgets: KnownLibs.componentsFor(['charts']),
        modulePrelude: KnownLibs.moduleStubFor(['charts']),
      );
    });

    test('le stub tolère un nombre d\'arguments variable', () async {
      final bundler = Bundler();
      await bundler.validate(
        'fn f() {\n'
        '  let a = charts.percent(1, 4)\n'
        '  let b = charts.formatNumber(1200)\n'
        '  let c = charts.niceScale(0, 10, 5)\n'
        '  return a\n'
        '}',
        modulePrelude: KnownLibs.moduleStubFor(['charts']),
      );
    });

    test('la validation seule ne voit rien dans un corps de fonction — c\'est '
        'pourquoi undeclaredUsage existe', () async {
      final bundler = Bundler();
      // Le moteur n'exécute que le premier niveau : ce LineChart non déclaré
      // passe. Sans analyse du source, l'oubli n'apparaîtrait qu'à l'exécution.
      await bundler.validate('fn build() { return LineChart({}) }');
    });
  });

  group('usage d\'un pack non déclaré', () {
    test('détecté dans un corps de fonction, là où on l\'utilise vraiment', () {
      final usage = KnownLibs.undeclaredUsage(
        'fn build() { return LineChart({ data: [1, 2] }) }',
        const [],
      );
      expect(usage, {'LineChart': 'charts'});
    });

    test('rien à signaler quand le pack est déclaré', () {
      final usage = KnownLibs.undeclaredUsage(
        'fn build() { return LineChart({}) }',
        const ['charts'],
      );
      expect(usage, isEmpty);
    });

    test('un module déréférencé est détecté', () {
      final usage = KnownLibs.undeclaredUsage(
        'fn f() { return media.pickImage("cb") }',
        const [],
      );
      expect(usage, {'media': 'media'});
    });

    test('un nom que le développeur définit lui-même est le sien', () {
      // Redéfinir LineChart est légitime : ce n'est pas celui de la lib.
      final usage = KnownLibs.undeclaredUsage(
        'fn LineChart(props) { return Text("maison") }\n'
        'fn build() { return LineChart({}) }',
        const [],
      );
      expect(usage, isEmpty);
    });

    test('ne confond pas un préfixe avec le composant', () {
      final usage = KnownLibs.undeclaredUsage(
        'fn build() { return MySparklineWrapper({}) }',
        const [],
      );
      expect(usage, isEmpty);
    });

    test('ne confond pas un membre de même nom', () {
      // `chart.Sparkline(...)` accède à un membre : ce n'est pas la globale.
      final usage = KnownLibs.undeclaredUsage(
        'fn build() { return monModule.Sparkline({}) }',
        const [],
      );
      expect(usage, isEmpty);
    });

    test('le message nomme le pack et la clé du manifeste', () {
      final message = KnownLibs.messageForUndeclaredUsage(
        {'LineChart': 'charts', 'MediaGrid': 'media'},
      );
      expect(message, contains('LineChart'));
      expect(message, contains('"requires"'));
      expect(message, contains('"charts", "media"'));
    });
  });

  group('conseil sur un pack oublié', () {
    test('nomme le composant, son pack et la clé à corriger', () {
      final hint = KnownLibs.hintForUndeclared(
        'Validation failed:\n  Undefined variable: LineChart',
        const [],
      );
      expect(hint, isNotNull);
      expect(hint, contains('LineChart'));
      expect(hint, contains('charts'));
      expect(hint, contains('requires'));
    });

    test('reste muet quand le pack est bien déclaré', () {
      final hint = KnownLibs.hintForUndeclared(
        'Validation failed:\n  Undefined variable: LineChart',
        const ['charts'],
      );
      expect(hint, isNull);
    });

    test('regroupe plusieurs packs manquants', () {
      final hint = KnownLibs.hintForUndeclared(
        'Undefined variable: LineChart\nUndefined variable: MediaGrid',
        const [],
      );
      expect(hint, contains('charts'));
      expect(hint, contains('media'));
      expect(hint, contains('les packs'));
    });

    test('ne se déclenche pas sur un nom qui contient celui d\'un composant',
        () {
      // "Sparkline" est un composant de charts, mais MySparklineWrapper est un
      // identifiant de l'utilisateur : le conseil serait trompeur.
      final hint = KnownLibs.hintForUndeclared(
        'Undefined variable: MySparklineWrapper',
        const [],
      );
      expect(hint, isNull);
    });

    test('reste muet sur une erreur sans rapport', () {
      final hint = KnownLibs.hintForUndeclared(
        'Unexpected token "}" at line 12',
        const [],
      );
      expect(hint, isNull);
    });
  });
}
