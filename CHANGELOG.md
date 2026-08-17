## 0.5.0

### La préview connaît QrCode

La préview web embarquée dans le binaire est reconstruite contre kmini_program
1.7.0. Sans ça, un `QrCode(...)` compilait, partait sur l'appareil, et ne
s'affichait pas dans `krom dev` — l'écart entre les deux ne se voyait qu'au
moment de tester.

## 0.4.0

### `krom init` demande ce qu'on ne lui a pas dit

La commande exigeait le nom du projet en argument et prenait le gabarit par
défaut sans jamais montrer les six autres. Elle pose désormais les questions —
nom, gabarit, et rattachement au backend quand la CLI est connectée. Flèches ou
`j`/`k`, chiffres `1`-`9` en raccourci, les extrémités bouclent.

Rien n'est demandé de ce qui a été écrit : `-t dashboard` ne rouvre pas la
liste. Et rien n'est demandé hors d'un terminal — une CLI qui bloque sur une
question dans un job CI ne se voit qu'au timeout, vingt minutes plus tard, sans
une ligne pour l'expliquer. Sans terminal, l'absence de nom reste l'erreur
qu'elle a toujours été, et tous les appels scriptés existants passent inchangés.

Le mode brut est rétabli dans un `finally` : sortir en laissant l'écho coupé
rend le shell inutilisable, et l'utilisateur n'a aucun moyen de deviner que
c'est nous. Ctrl+C rétablit puis sort en 130.

### La CLI dit son nom

Un outil qu'on installe par `curl | sh` n'a qu'un endroit pour se présenter :
la première commande qu'on tape. `krom init` et `krom` nu affichent le mot KROM
en blocs, dans le vert-sarcelle de l'accent du guide, avec la version.

Rien n'en sort quand la sortie n'est pas un terminal, et `krom --version` reste
la ligne unique que le script d'installation lit.

### Des encadrés qui se ferment

Le serveur de dev et le résumé de build passent d'un titre souligné à un
encadré, l'URL du serveur seule en gras — c'est ce qu'on vient chercher des
yeux pour la copier. La largeur se calcule sur du texte non coloré : une
séquence ANSI déjà posée fausserait le compte et décalerait la bordure d'autant
de caractères qu'il y a de codes.

### Le logger connaît enfin NO_COLOR

Il décidait de colorer sur `stdout.hasTerminal` seul, et écrivait donc des
séquences ANSI aux CI qui demandent `NO_COLOR`, et aux terminaux qui annoncent
`TERM=dumb` n'interpréter aucune séquence. Elles y ressortaient en caractères
parasites.

## 0.3.20

### Un tag qui ne correspond pas à la source ne publie plus

La version est écrite à trois endroits : `pubspec.yaml`, la constante
`kromVersion`, et le tag git. La 0.3.18 a ajouté un test qui garde les deux
fichiers d'accord — mais rien ne les reliait au tag, et 0.3.19 est partie avec
un binaire qui annonçait `0.3.18`.

Le workflow de release compare désormais les trois avant de construire quoi que
ce soit. Un tag mal aligné échoue avec les trois valeurs affichées, au lieu de
publier un binaire qui ment sur son propre nom — ce qui donne à qui réinstalle
l'impression que rien ne s'est passé.

Publier est irréversible ; échouer avant ne coûte qu'un tag à refaire.

## 0.3.18

### `krom --version` dit la vérité

La version vit à deux endroits : `pubspec.yaml` et la constante `kromVersion`
de `bin/krom_bundler.dart`, celle que la commande affiche. Rien ne les liait.

Les binaires 0.3.16 et 0.3.17 étaient les bons — code, assets, tout — mais
annonçaient `krom 0.3.15`, ce qui donne exactement l'impression que
l'installation a échoué. Constante remise d'aplomb, et un test la compare
désormais au pubspec : la dérive ne peut plus repartir en release.

Aucun changement de comportement. Si vous aviez installé 0.3.16 ou 0.3.17, le
binaire faisait déjà ce qu'il fallait.

## 0.3.17

### `krom dev --remote` envoie les assets

Le canal ne transportait que le script. Sur l'appareil, une image du projet
s'affichait en carré gris — alors qu'elle marchait dans la préview web, où le
serveur de dev sert déjà les fichiers du projet. L'écart ne se voyait qu'au
moment de tester pour de vrai.

Le push joint maintenant la carte d'intégrité des assets, le backend répond ce
qui lui manque, et le CLI n'envoie que ça. Le premier push porte le média ;
les suivants ne portent rien tant qu'aucun fichier n'a changé, donc le
rechargement à chaud reste à la vitesse du bundle.

Le watcher suit aussi `assets/` : retoucher un logo pousse la nouvelle image
comme une sauvegarde de `.ks` pousse le nouveau code.

Demande **kmini_program 1.6.7** côté hôte, et le backend qui sert la route.

## 0.3.16

### `@use "…" as ns` — les imports ont enfin une portée

`@use` recopiait le fichier importé dans la portée de l'importeur. Deux
fichiers déclarant `let T` se marchaient dessus en silence, et la valeur que
lisait une fonction dépendait de l'ordre des imports : le dernier fichier
écrasait le premier, sans erreur ni avertissement.

La nouvelle forme donne un nom au module :

```
@use "utils/ui.ks" as styles

fn build() { return Box({ color: styles.T.bg }) }
```

Le bundler compile le module en fermeture et en expose les déclarations de
premier niveau. Deux modules peuvent désormais déclarer le même nom. Le module
n'est émis qu'une fois, quel que soit le nombre d'importeurs, chacun gardant
son propre alias.

La forme sans `as` ne bouge pas d'un octet — vérifié en rebuildant un projet
existant et en comparant les scripts produits.

### Ce que le bundler refuse maintenant

- un module importé à la fois avec et sans `as` ;
- un alias qui désigne deux modules différents ;
- un alias qui recouvre un widget, un `customWidget` ou un namespace de l'hôte
  (`ui`, `nav`, `theme`, `storage`, `device`, `timer`, `request`, `args`) ;
- **un fichier qui utilise l'alias d'un autre fichier.** Le bundle est plat, le
  nom s'y résoudrait ; mais le jour où les modules deviendront une notion du
  langage, cette portée-là disparaîtra. Autant l'interdire tout de suite que
  laisser du code s'installer dessus.

### Migrer

Un appel par nom doit être qualifié, y compris quand la fonction vit dans le
fichier qui la nomme :

```
{ builder: "homeTab" }             → { builder: "homeView.homeTab" }
```

Demande **krom_script 1.0.4** : c'est lui qui résout les noms pointés à
l'invocation, et qui garde un alias vivant à l'optimisation quand la seule
référence est dans une chaîne.

### `krom build --stats`

Chaque page est une unité autonome — le runtime lui donne son propre moteur,
sans rien partager — donc un module importé par trois pages part trois fois.
Le drapeau dit ce que ça coûte vraiment :

```
  Duplication des modules
  ───────────────────────
    utils/ui.ks      3.6 KB  × 3  →   7.1 KB en trop
    utils/data.ks    2.4 KB  × 2  →   2.4 KB en trop

    Sortie         22.7 KB brut, 5.2 KB gzip
    Transporté     6.8 KB gzip
    Dédupliqué     6.7 KB gzip — 0.1 KB de gain, 2.2 %
```

Sur `spi`, le projet le plus partageur du corpus, dédupliquer économiserait
**2,2 %**. Dans un flux compressé unique, les copies d'un module sont des
références arrière : elles ne coûtent presque rien. Le rapport le dit, plutôt
que de laisser croire à un gain.

À quoi ça sert : décider d'un système de chunks partagés — qui coûterait un
changement de format `dist` — sur des chiffres et non sur une intuition. Le
rapport rappelle aussi que le gain ne porterait que sur le transport : un
module partagé sera de toute façon réévalué à chaque ouverture de page.

## 0.3.15

- Préview embarquée reconstruite sur **kmini_program 1.6.5** : `ListView` passe
  de 1 à 11 props (séparateurs, pagination, `shrinkWrap`/`physics`),
  `ui.scrollTo` existe, et `disabled` veut enfin dire quelque chose sur
  `Switch`, `Checkbox`, `Slider`, `RadioGroup` et `Segmented`.

## 0.3.14

- Préview embarquée reconstruite sur **kmini_program 1.6.4**. Ce que la préview
  ignorait jusque-là : `Positioned` et les neuf alignements d'un `Stack`, les
  dix props de `Image` (opacité, teinte, coins arrondis, décodage à la taille
  affichée), le champ de saisie et les surfaces modales qui suivent le thème de
  l'hôte, et la capsule à deux zones — « ••• » ouvre le menu, « ✕ » ferme.

  Sans cette reconstruction, `krom dev` affichait ces props comme si elles
  n'existaient pas, sans erreur, et `Positioned` y était une variable
  indéfinie.

## 0.3.13

- Préview embarquée reconstruite sur **kmini_program 1.6.0**. Ce qui a été
  ajouté au champ texte s'y rend enfin : le masque (`mask: "## ## ## ##"`), le
  groupage des milliers (`thousands`), un widget libre en préfixe ou suffixe,
  le style du champ et du bouton. Sans cette reconstruction, `krom dev`
  affichait ces props comme si elles n'existaient pas — sans erreur.

## 0.3.12

- Préview embarquée reconstruite sur **kmini_program 1.5.4** / **krom_script
  1.0.3**. Une erreur d'exécution y affiche désormais `at pages/home.ks:2` au
  lieu d'un message sans position — dernier maillon de la chaîne ouverte en
  0.3.9 côté build.

- La CLI elle-même passe à **krom_script 1.0.3**. Bénéfice direct : une erreur
  de **validation** (le code de premier niveau, exécuté au build) porte enfin
  sa position, et la table la situe — `undefined variable: paletteInexistante
  at pages/home.ks:3` au lieu d'un message muet.

## 0.3.11

### La table voyage jusqu'au device

- `krom dev` écrit dans chaque page du manifeste la table
  `ligne du bundle → fichier:ligne` (clés `f`/`d`/`n`). Le SDK la relit et
  situe ses erreurs **d'exécution** : `at pages/home.ks:180:31` dans la
  préview web comme sur un device via le canal de dev. Jusqu'ici seules les
  erreurs de build étaient situées.

- Réservé au développement. `krom build` et `krom publish` n'en émettent pas :
  leur sortie est optimisée — le texte est réécrit, la table n'y
  correspondrait plus.

- Préview embarquée reconstruite sur **kmini_program 1.5.3**.

## 0.3.10

- Préview embarquée reconstruite sur **kmini_program 1.5.2**, qui décompte
  aussi le prélude injecté par l'hôte : les erreurs d'exécution affichées dans
  la préview tombent sur les lignes du script de la mini-app.

## 0.3.9

### Les erreurs pointent la ligne du fichier, pas celle du bundle

- Le bundle est une concaténation : les `@use` (résolus transitivement) puis la
  page, chacun précédé d'une ligne d'en-tête. Le moteur numérotait donc **le
  bundle**, et une virgule oubliée à la ligne 180 de `pages/home.ks` était
  annoncée « at line 207 » — 27 lignes plus bas, sans rien pour faire le
  rapprochement. Une seule faute pouvant partir en trente messages en cascade,
  il fallait deviner lequel comptait *et* où il pointait vraiment.

  Le bundler tient maintenant une table `ligne du bundle → fichier:ligne`, et
  les erreurs sortent en `at pages/home.ks:180:31` — cliquable depuis le
  terminal comme depuis VSCode. Vaut pour `krom build`, `krom dev`, et les
  erreurs de rebuild poussées à la préview et aux devices connectés.

- Les directives `@use` sont **blanchies plutôt que supprimées**. Elles
  laissaient un trou : tout ce qui suivait un import était déjà décalé avant
  même la concaténation.

- Une position qu'aucune table ne situe garde son numéro brut. C'est le cas
  après optimisation ou minification (`krom build`), où le texte est réécrit :
  mieux vaut un numéro de bundle honnête qu'un numéro de fichier faux.

## 0.3.8

### Préview embarquée — les enfants dans les props

- La préview web embarquée est reconstruite sur **kmini_program 1.5.0**, où les
  enfants d'un composant passent par `child:` / `children:` dans les props.
  L'ancienne préview datait d'avant : elle exécutait le prélude précédent, qui
  ignore ces clés — un `Column({ children: [...] })` s'y affichait **vide, sans
  message d'erreur**. C'est le seul changement fonctionnel de cette version ; le
  CLI lui-même est inchangé.

- La forme héritée (les enfants en 2ᵉ argument positionnel) rend toujours à
  l'identique : le prélude 1.5.0 l'accepte sans date de fin.

## 0.3.7

### Descripteurs embarqués — `nenga_form` 0.6.1

- Le bundler connaît désormais les opérations de **reprise de brouillon** du pack
  `nenga_form` : `nenga.newDraft(formKey)`, `nenga.latestDraft`,
  `nenga.discardDraft` et `nenga.submit` sont validées au build au lieu de
  produire un « méthode inconnue ». Régénéré depuis `krom_lib_nenga_form` 0.6.1
  via `dart run tool/embed_lib_descriptors.dart`.

## 0.3.5

### `krom dev --remote` — tester en direct sur appareil ou émulateur

- **Nouveau flag `krom dev --remote`** : ouvre un *canal de dev* éphémère sur le
  backend, affiche un code court à saisir dans l'app hôte (pas de scan → marche
  sur émulateur), puis pousse le manifeste rebundlé à chaque sauvegarde. La
  mini-app se recharge à chaud dans la vraie super-app, sans publication ni
  nouvelle version. Erreur de build poussée en overlay sur l'appareil ; canal
  expiré → message clair.
- **`BackendClient`** gagne `openDevChannel` / `pushDevBundle` / `pushDevError`
  et le modèle `DevChannel`.

## 0.3.4

### Les packs `arcade` et `nenga_form` connus de l'outillage, préview à jour

- **Descripteurs `arcade` et `nenga_form` embarqués** : `krom build` et
  `krom dev` connaissent désormais deux packs de plus — `arcade` (gamification :
  `SpinWheel`, `ScratchCard`, `MysteryBox` + module `play`) et `nenga_form`
  (`NengaForm`, formulaire dynamique rendu depuis une définition à spec
  distante). Utiliser l'un de leurs composants sans déclarer le `requires`
  correspondant produit une erreur **nommée** au build, au lieu d'un « undefined
  variable » à l'exécution. Le catalogue outillé passe à **6 packs** (charts,
  media, forms, sensors, arcade, nenga_form).
- **Préview réembarquée** : `krom dev` rend maintenant réellement les composants
  `arcade` et `nenga_form`, et embarque le SDK 1.2.0 — donc le décorateur
  universel `mod` sur tout widget.

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
