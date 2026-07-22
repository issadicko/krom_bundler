import 'lib_descriptors.g.dart';

export 'lib_descriptors.g.dart' show KromLibDescriptor, kKromLibDescriptors;

/// Ce que l'outillage sait des libs de domaine embarquées.
///
/// Les descripteurs sont compilés dans le binaire (voir
/// `tool/embed_lib_descriptors.dart`), donc `krom build` et `krom dev`
/// connaissent `LineChart` ou `media.pickImage` sans que le développeur n'ait
/// rien à installer ni à fetcher. Du point de vue des outils, une lib se
/// comporte comme le core.
///
/// Elle ne l'est pas pour autant : c'est toujours le `requires` du manifeste qui
/// ouvre un pack, et la super-app qui décide de le brancher. Cette classe sert
/// précisément à rendre cet écart lisible — quand un composant connu est utilisé
/// sans son pack, on peut le nommer au lieu de laisser passer un « undefined
/// variable » incompréhensible.
class KnownLibs {
  const KnownLibs._();

  /// Les packs embarqués, dans l'ordre du descripteur généré.
  static Iterable<String> get packs => kKromLibDescriptors.keys;

  /// Le pack qui fournit le composant [name], ou `null` s'il est inconnu.
  static String? packOfComponent(String name) {
    for (final entry in kKromLibDescriptors.entries) {
      if (entry.value.components.contains(name)) return entry.key;
    }
    return null;
  }

  /// Le pack qui fournit le module [name], ou `null` s'il est inconnu.
  static String? packOfModule(String name) {
    for (final entry in kKromLibDescriptors.entries) {
      if (entry.value.modules.containsKey(name)) return entry.key;
    }
    return null;
  }

  /// Tous les composants apportés par les packs [declared] — ce qui vient
  /// s'ajouter aux `customWidgets` du manifeste, sans que l'auteur les liste.
  static List<String> componentsFor(Iterable<String> declared) {
    final out = <String>[];
    for (final pack in declared) {
      final descriptor = kKromLibDescriptors[pack];
      if (descriptor != null) out.addAll(descriptor.components);
    }
    return out;
  }

  /// Le stub KromScript des modules apportés par les packs [declared].
  ///
  /// Sans lui, un appel comme `charts.palette(5)` posé au niveau racine d'un
  /// fichier échouerait à la validation — le bundler exécute le code de premier
  /// niveau et n'a pas les modules de l'hôte. Ce n'était pourtant jamais une
  /// vraie limite : à l'exécution, les bindings sont injectés **avant** le
  /// chargement du script. Stuber les modules ici supprime donc une contrainte
  /// qui n'existait qu'à cause de l'outillage.
  ///
  /// Chaque méthode déclarée est stubée en `fn(...) { return null }` variadique
  /// approximée : le nombre d'arguments n'est pas contraint à la validation.
  static String moduleStubFor(Iterable<String> declared) {
    final buffer = StringBuffer();
    for (final pack in declared) {
      final descriptor = kKromLibDescriptors[pack];
      if (descriptor == null) continue;
      descriptor.modules.forEach((module, methods) {
        final entries =
            methods.map((m) => '$m: fn(a, b, c) { return null }').join(', ');
        buffer.writeln('let $module = { $entries }');
      });
    }
    return buffer.toString();
  }

  /// Les noms de libs utilisés par [source] alors que leur pack n'est pas dans
  /// [declared], sous la forme `nom -> pack`.
  ///
  /// La validation du bundler n'exécute que le code de **premier niveau** : un
  /// `LineChart(...)` posé dans `fn build()` — c'est-à-dire l'usage normal — n'y
  /// déclenche aucune erreur. Sans cette analyse, oublier `"requires"` ne se
  /// verrait qu'à l'exécution, sur un écran vide. On lit donc le source
  /// directement.
  ///
  /// Un nom que le développeur définit lui-même (`fn LineChart`, `let LineChart`)
  /// est ignoré : c'est le sien, pas celui de la lib.
  static Map<String, String> undeclaredUsage(
    String source,
    Iterable<String> declared,
  ) {
    final declaredSet = declared.toSet();
    final found = <String, String>{};

    kKromLibDescriptors.forEach((pack, descriptor) {
      if (declaredSet.contains(pack)) return;
      for (final component in descriptor.components) {
        if (_isCalled(source, component) && !_isDefinedLocally(source, component)) {
          found[component] = pack;
        }
      }
      for (final module in descriptor.modules.keys) {
        if (_isDereferenced(source, module) &&
            !_isDefinedLocally(source, module)) {
          found[module] = pack;
        }
      }
    });
    return found;
  }

  /// Le message d'erreur pour un usage relevé par [undeclaredUsage].
  static String messageForUndeclaredUsage(Map<String, String> usage) {
    final packs = usage.values.toSet().toList()..sort();
    final names = usage.keys.toList()..sort();
    final plural = packs.length > 1;
    return 'Librairie de domaine non déclarée.\n'
        '  ${names.map((n) => '$n → pack "${usage[n]}"').join('\n  ')}\n\n'
        'Ajoute ${plural ? 'ces packs' : 'ce pack'} à "requires" dans '
        'manifest.json :\n'
        '  "requires": [${packs.map((p) => '"$p"').join(', ')}]\n\n'
        'La super-app doit également ${plural ? 'les avoir branchés' : "l'avoir branché"} '
        '— sinon la mini-app sera refusée au lancement.';
  }

  /// `Nom(` — un appel, pas une sous-chaîne ni un accès à un membre.
  static bool _isCalled(String source, String name) =>
      RegExp('(?<![A-Za-z0-9_.])${RegExp.escape(name)}\\s*\\(').hasMatch(source);

  /// `nom.` — l'usage d'un namespace.
  static bool _isDereferenced(String source, String name) =>
      RegExp('(?<![A-Za-z0-9_.])${RegExp.escape(name)}\\s*\\.').hasMatch(source);

  /// `let nom` / `fn nom` — le développeur a défini ce nom lui-même.
  static bool _isDefinedLocally(String source, String name) => RegExp(
        '(?:let|fn)\\s+${RegExp.escape(name)}(?![A-Za-z0-9_])',
      ).hasMatch(source);

  /// Un conseil actionnable si [errors] met en cause un nom connu dont le pack
  /// n'est pas déclaré dans [declared], sinon `null`.
  ///
  /// C'est le rattrapage de l'erreur la plus probable : utiliser `LineChart`
  /// sans avoir écrit `"requires": ["charts"]`. Le message brut du moteur
  /// n'aide pas — celui-ci nomme le pack et la clé à corriger.
  static String? hintForUndeclared(
    String errors,
    Iterable<String> declared,
  ) {
    final declaredSet = declared.toSet();
    final culprits = <String, String>{}; // nom -> pack

    kKromLibDescriptors.forEach((pack, descriptor) {
      if (declaredSet.contains(pack)) return;
      for (final component in descriptor.components) {
        if (_mentions(errors, component)) culprits[component] = pack;
      }
      for (final module in descriptor.modules.keys) {
        if (_mentions(errors, module)) culprits[module] = pack;
      }
    });

    if (culprits.isEmpty) return null;

    final packsNeeded = culprits.values.toSet().toList()..sort();
    final names = culprits.keys.toList()..sort();
    final quoted = packsNeeded.map((p) => '"$p"').join(', ');

    return 'Ces noms viennent de librairies de domaine : '
        '${names.map((n) => '$n (${culprits[n]})').join(', ')}.\n'
        'Ajoute ${packsNeeded.length > 1 ? 'les packs' : 'le pack'} $quoted à '
        '"requires" dans manifest.json — et assure-toi que la super-app '
        '${packsNeeded.length > 1 ? 'les a branchés' : "l'a branché"}.';
  }

  /// Vrai si [errors] cite [name] comme identifiant, et non en sous-chaîne d'un
  /// autre mot (`Sparkline` ne doit pas matcher dans `MySparklineWrapper`).
  static bool _mentions(String errors, String name) {
    final pattern = RegExp('(?<![A-Za-z0-9_])${RegExp.escape(name)}'
        '(?![A-Za-z0-9_])');
    return pattern.hasMatch(errors);
  }
}
