## 0.3.3

### Le pack `sensors` connu de l'outillage, preview à jour

- **Descripteur `sensors` embarqué** : `krom build` et `krom dev` connaissent
  désormais le 4ᵉ pack de domaine — les modules `deviceState` (batterie, réseau),
  `biometric` (empreinte/visage) et `location` (position, distance, géo-agents).
  Appeler `location.current(...)` ou `deviceState.battery(...)` sans déclarer
  `"requires": ["sensors"]` produit une erreur **nommée** au build, au lieu d'un
  « undefined variable » à l'exécution. Les sous-permissions `sensors.location`
  et `sensors.biometric` restent à déclarer dans `permissions`.
- **Preview réembarquée** : le rendu de `krom dev` branche maintenant les
  **quatre** libs (charts, media, forms, **sensors**) sur le core à jour
  (kmini_program 1.1.4). Une mini-app qui déclare `sensors` s'ouvre donc dans la
  préview web ; faute de matériel branché côté navigateur, les capteurs y
  répondent « indisponible » — mais le gating et l'UI restent fidèles à ce que
  rendra Krom Go ou une super-app qui a câblé les adapters natifs.

## 0.3.2

### Le preview ne vole plus le focus de l'éditeur

- **Garde-focus injecté dans la page servie par `krom dev`** : le moteur
  Flutter web appelle `focus()` au démarrage et à chaque hot reload — dans le
  webview Device Preview de VSCode (ou un onglet en arrière-plan), chaque
  sauvegarde arrachait donc le focus clavier à l'éditeur. Les `focus()`
  programmatiques ne sont désormais honorés que si la page de preview est
  réellement utilisée (page déjà focalisée, ou interaction pointeur/clavier
  dans les 3 dernières secondes). Le focus natif — cliquer dans le preview —
  n'est pas affecté, et un tap dans un champ du preview continue d'ouvrir le
  clavier normalement.

## 0.3.1

### Descripteurs et preview à jour

- **Descripteurs embarqués régénérés** : le pack `forms` passe à **1.2.0** —
  `pickContact` et `PhoneField({ pickContact })` sont désormais connus de
  `krom build` et `krom dev` (validation, autocomplétion via l'outillage).
- **Preview réembarquée sur kmini_program 1.1.2** : le rendu de `krom dev`
  reflète les derniers widgets du core — `Padding`, prefix/suffix cliquables du
  `TextField` (`onPrefixTap`/`onSuffixTap`), et `Obx({ builder, args })`.

## 0.3.0

### Les libs de domaine deviennent natives pour l'outillage

- **Descripteurs embarqués** : les `krom_lib.json` de `charts`, `media` et `forms`
  sont compilés dans le binaire (`tool/embed_lib_descriptors.dart`). `krom build`
  et `krom dev` connaissent leurs composants et leurs modules sans que le
  développeur n'installe ni ne récupère quoi que ce soit.
- **Plus besoin de déclarer `customWidgets`** pour un composant de lib :
  déclarer le pack dans `requires` suffit désormais à ce que `LineChart` ou
  `MediaGrid` soit connu à la compilation, exactement comme un widget du core.
- **Un appel de module au niveau racine d'un `.ks` est enfin valide**
  (`let couleurs = charts.palette(5)`). Ce n'avait jamais été une vraie limite :
  à l'exécution, les bindings sont injectés **avant** le chargement du script.
  C'était un angle mort du bundler, qui validait le premier niveau sans les
  modules de l'hôte.
- **Erreur nommée sur un pack oublié** : utiliser `LineChart` sans avoir déclaré
  `"charts"` produit un message qui donne le composant, son pack et la clé à
  corriger — au lieu d'un « undefined variable ». La détection lit le source, et
  couvre donc l'usage réel, à l'intérieur des fonctions, que la validation du
  moteur ne voit pas (elle n'exécute que le premier niveau).

### Préview : le thème de la mini-app se choisit

- **La mini-app était rendue en sombre, sans alternative.** La préview appliquait
  son propre `ThemeData.dark` à tout, y compris à l'app rendue : impossible de
  vérifier l'aspect clair, alors que les composants se thématisent sur ce
  `colorScheme` et que la variable `theme` de KromScript en dérive. La mini-app a
  désormais son thème propre, **clair par défaut**, indépendant du chrome de
  l'outil — qui reste sombre, c'est un outil de dev.
- **Bascule clair/sombre** dans le panneau device, et paramètre d'URL
  `?theme=dark` pour le mode `view=device`, où il n'y a pas de chrome (extension
  VSCode, captures automatisées).

### Corrections

- **`requires` et `minSdk` étaient supprimés du manifeste compilé.** Toute la
  garde de compatibilité du SDK reposait dessus : sans eux dans la sortie, le
  runtime ne pouvait ni refuser proprement une mini-app dont l'hôte n'avait pas
  branché la lib, ni lui accorder le pack déclaré. Les composants restaient
  simplement introuvables à l'exécution.
- **`krom dev` prévient quand un `web_build/` sur disque masque la préview
  embarquée** et en diffère. La comparaison porte sur le **contenu** de
  `main.dart.js`, pas sur `.last_build_id` : ce marqueur est un hash de
  configuration, identique entre deux builds du même projet à des semaines
  d'écart — s'y fier laissait passer précisément le cas à détecter. Cette précédence est voulue pour qui développe la
  préview, mais un dossier oublié sert silencieusement une version périmée — et
  le symptôme est déroutant : un composant pourtant embarqué s'affiche en
  placeholder, ou une syntaxe pourtant supportée est refusée.

## 0.2.0

### Templates `krom init`

- **3 nouveaux templates** : `form` (champs + Select + Switch + résumé réactif + envoi), `dashboard` (cartes de stats + BarChart + Gauge) et `onboarding` (carrousel PageView + points + bouton).
- **Templates existants améliorés** : `default` entièrement **thématisé** (suit le thème clair/sombre de l'hôte) et débarrassé du champ `utils` déprécié du manifeste ; `tabbed` gagne des libellés d'onglets + une carte solde ; `list-detail` gagne une AppBar.
- Tous les templates sont vérifiés au rendu sur le preview Galaxy S24 et bundlés par la CI (`init_templates_test.dart`).

### Preview

- **Preview embarqué régénéré** (`preview_assets.g.dart`) contre `krom_script 1.0.1` : le runtime du preview supporte désormais l'**opérateur ternaire `? :`** (et le reste de la syntaxe 1.0).

## 0.1.1

- Dépendance `krom_script` résolue depuis **pub.dev** (au lieu du dépôt git krom-lang) — la CI n'a plus besoin d'accéder au repo pour construire les binaires.

## 0.1.0

- Distribution binaire multi-OS + installeur `curl | sh`.
- Initial version.
