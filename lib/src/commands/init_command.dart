import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;
import '../backend/backend_client.dart';
import '../backend/project_ref.dart';
import '../utils/config.dart';
import '../utils/logger.dart';

/// Init command - creates a new mini-app project.
///
/// When the CLI is connected (remote + PAT), the app is also created on the
/// backend right away and its canonical UUID is written into the manifest as
/// `appId` — the project is born linked. Offline (or with `--no-link`), the
/// scaffold still works and `krom link` (or the first publish) attaches later.
class InitCommand extends Command<int> {
  @override
  final name = 'init';

  @override
  final description = 'Create a new KromLang mini-app project';

  @override
  String get invocation => 'krom init <project_name>';

  InitCommand() {
    argParser
      ..addFlag('link',
          defaultsTo: true,
          help: 'Also create the app on the backend (when connected) and write '
              'its "appId" into the manifest.')
      ..addOption('template',
          abbr: 't',
          help: 'Project template.',
          allowed: ['default', 'tabbed', 'list-detail', 'form', 'dashboard', 'onboarding'],
          allowedHelp: {
            'default': 'Themed starter: a welcome card and a reactive counter.',
            'tabbed': 'Floating tab bar (TabHostNav), one component per tab.',
            'list-detail': 'A list page navigating to a detail page (args).',
            'form': 'A form: text field, select, switch, live summary and submit.',
            'dashboard': 'A data dashboard: stat cards, BarChart and Gauge.',
            'onboarding': 'A PageView carousel with dots and a "Get started" button.',
          },
          defaultsTo: 'default');
  }

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      Logger.bundleError(
        message: 'Missing project name',
        suggestion: 'Usage: krom init <project_name>',
      );
      return 1;
    }

    final projectName = argResults!.rest.first;

    // Validate project name
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]*$').hasMatch(projectName)) {
      Logger.bundleError(
        message: 'Invalid project name: "$projectName"',
        suggestion:
            'Use only letters, numbers, hyphens, and underscores. Must start with a letter.',
      );
      return 1;
    }

    final projectDir = Directory(projectName);

    if (await projectDir.exists()) {
      Logger.bundleError(
        message: 'Directory "$projectName" already exists',
        suggestion: 'Choose a different name or delete the existing directory.',
      );
      return 1;
    }

    Logger.header('Creating mini-app: $projectName');

    final template = argResults!['template'] as String;

    try {
      Logger.step(1, 3, 'Creating project structure ($template)...');
      final files = templateFiles(template, projectName);
      for (final entry in files.entries) {
        final file = File(p.join(projectName, entry.key));
        await file.parent.create(recursive: true);
        await file.writeAsString(entry.value);
      }
      await Directory(p.join(projectName, 'assets', 'images'))
          .create(recursive: true);

      Logger.step(2, 3, 'Creating README...');
      await File(p.join(projectName, 'README.md'))
          .writeAsString(_readmeTemplate(projectName));

      Logger.step(3, 3, 'Done.');
      Logger.newline();
      Logger.success('Project "$projectName" created!');
      Logger.newline();
      for (final path in files.keys) {
        Logger.fileCreated('$projectName/$path');
      }
      Logger.fileCreated('$projectName/README.md');
      Logger.newline();

      await _linkToBackend(projectName);

      Logger.info('Next steps:');
      Logger.hint('cd $projectName');
      Logger.hint('krom dev');
      Logger.newline();

      return 0;
    } catch (e) {
      Logger.error('Failed to create project: $e');
      return 1;
    }
  }

  /// Creates the app on the backend (find-or-create by slug) and writes its
  /// UUID into the fresh manifest. Best-effort: any failure downgrades to a
  /// hint pointing at `krom link` — init never fails because of the network.
  Future<void> _linkToBackend(String projectName) async {
    if (!(argResults!['link'] as bool)) return;
    final config = KromConfig();
    if (config.remoteUrl == null ||
        config.remoteUrl!.isEmpty ||
        !config.isAuthenticated) {
      Logger.hint(
          'Not connected to a backend — link later with "krom link".');
      Logger.newline();
      return;
    }

    final client =
        BackendClient(baseUrl: config.remoteUrl!, token: config.authToken!);
    try {
      final existing = await client.findAppBySlug(projectName);
      final app = existing ??
          await client.createApp(
              name: _toTitleCase(projectName), slug: projectName);
      ManifestRef.load(p.join(projectName, 'manifest.json'))
          .writeAppId(app.id);
      Logger.success(existing != null
          ? 'Attached to the existing backend app "$projectName" (${app.id}).'
          : 'Created "$projectName" on ${config.remoteUrl} (appId ${app.id}).');
    } catch (e) {
      Logger.warn('Could not create the app on the backend: $e');
      Logger.hint('Link it later with "krom link" (from the project folder).');
    } finally {
      client.close();
    }
    Logger.newline();
  }

  /// All source files of [template], path → content. Exposed (not private)
  /// so tests can scaffold each template and run it through the bundler.
  Map<String, String> templateFiles(String template, String projectName) {
    switch (template) {
      case 'tabbed':
        return {
          'manifest.json': _tabbedManifest(projectName),
          'pages/home.ks': _tabbedShell,
          'utils/ui.ks': _themeUtils,
          'utils/components/home_tab.ks': _tabbedHomeTab,
          'utils/components/explore_tab.ks': _tabbedExploreTab,
          'utils/components/profile_tab.ks': _tabbedProfileTab,
        };
      case 'list-detail':
        return {
          'manifest.json': _listDetailManifest(projectName),
          'pages/list.ks': _listPage,
          'pages/detail.ks': _detailPage,
          'utils/ui.ks': _themeUtils,
          'utils/data.ks': _listData,
        };
      case 'form':
        return {
          'manifest.json': _singlePageManifest(projectName, 'form', 'edit'),
          'pages/form.ks': _formPage,
          'utils/ui.ks': _themeUtils,
        };
      case 'dashboard':
        return {
          'manifest.json': _singlePageManifest(projectName, 'dashboard', 'dashboard'),
          'pages/dashboard.ks': _dashboardPage,
          'utils/ui.ks': _themeUtils,
        };
      case 'onboarding':
        return {
          'manifest.json': _singlePageManifest(projectName, 'onboarding', 'star'),
          'pages/onboarding.ks': _onboardingPage,
          'utils/ui.ks': _themeUtils,
        };
      default:
        return {
          'manifest.json': _manifestTemplate(projectName),
          'pages/home.ks': _homePageTemplate,
          'components/app_button.ks': _buttonComponentTemplate,
          'utils/ui.ks': _themeUtils,
        };
    }
  }

  /// Manifest for a single-page template whose entry page is [page] (source
  /// `pages/<page>.ks`) shown with the [icon] tab glyph. No deprecated `utils`
  /// array — shared code is pulled in per page via `@use`.
  String _singlePageManifest(String projectName, String page, String icon) => '''{
  "id": "$projectName",
  "name": "${_toTitleCase(projectName)}",
  "version": "1.0.0",
  "description": "A KromLang mini-app",
  "author": "",
  "entry": "$page",
  "pages": {
    "$page": {
      "name": "${_toTitleCase(projectName)}",
      "source": "pages/$page.ks",
      "icon": "$icon"
    }
  },
  "permissions": []
}
''';

  // --- tabbed template ------------------------------------------------------

  String _tabbedManifest(String projectName) => '''{
  "id": "$projectName",
  "name": "${_toTitleCase(projectName)}",
  "version": "1.0.0",
  "description": "A tabbed KromLang mini-app",
  "author": "",
  "entry": "home",
  "pages": {
    "home": {
      "name": "${_toTitleCase(projectName)}",
      "source": "pages/home.ks",
      "icon": "home"
    }
  },
  "permissions": []
}
''';

  static const _tabbedShell = '''// Shell: a floating tab bar; each tab lives in utils/components/*.
// Builders are referenced BY NAME ({ builder: "homeTab" }) — always use this
// property form so the optimizer keeps them.
@use "../utils/ui.ks"
@use "../utils/components/home_tab.ks"
@use "../utils/components/explore_tab.ks"
@use "../utils/components/profile_tab.ks"

fn build() {
  return Scaffold({ backgroundColor: T.bg },
    TabHostNav({
        floating: true,
        showLabels: true,
        backgroundColor: T.card,
        selectedColor: T.primary,
        unselectedColor: T.muted,
        tabs: [
          { icon: "home",   label: "Accueil",  builder: "homeTab" },
          { icon: "store",  label: "Explorer", builder: "exploreTab" },
          { icon: "person", label: "Profil",   builder: "profileTab" }
        ]
    })
  )
}
''';

  /// Shared palette derived from the host theme — follows light/dark
  /// automatically. Used by every template except `default`.
  static const _themeUtils = '''// Palette dérivée du thème de l'hôte (suit clair/sombre automatiquement).
let T = {
  bg:      theme.surfaceContainerLow,
  card:    theme.surfaceContainerLowest,
  text:    theme.onSurface,
  muted:   theme.onSurfaceVariant,
  line:    theme.outlineVariant,
  primary: theme.primary
}

fn sectionTitle(label) {
  return Text(label, { fontSize: 16, fontWeight: "bold", color: T.text })
}

fn card(child) {
  return Box({ color: T.card, borderRadius: 16, padding: 16 }, [ child ])
}
''';

  static const _tabbedHomeTab = '''// Onglet Home : un compteur réactif pour démarrer.
@use "../ui.ks"

let counter = Obs(0)

fn homeTab() {
  return ScrollView({ padding: { left: 16, right: 16, top: 16, bottom: 110 } },
    Column({ spacing: 16, crossAxisAlignment: "stretch" }, [
        sectionTitle("Bienvenue 👋"),
        Box({ gradient: { from: T.primary, to: T.primary, angle: 45 },
              borderRadius: 18, padding: 20 },
          Column({ spacing: 4, crossAxisAlignment: "start" }, [
              Text("Solde disponible", { color: "#FFFFFFCC", fontSize: 13 }),
              Text("45 000 F CFA", { color: "#FFFFFF", fontSize: 26, fontWeight: "bold" })
          ])),
        card(Column({ spacing: 10, crossAxisAlignment: "center" }, [
            Text("Compteur réactif", { color: T.muted, fontSize: 13 }),
            Obx({ builder: "counterValue" }),
            Button("Incrémenter", { onTap: "increment", color: T.primary })
        ]))
    ])
  )
}

fn counterValue() {
  return Text("" + counter.value, { fontSize: 32, fontWeight: "bold", color: T.text })
}

fn increment() {
  counter.set(counter.value + 1)
}
''';

  static const _tabbedExploreTab = '''// Onglet Explore.
@use "../ui.ks"

fn exploreTab() {
  return ScrollView({ padding: { left: 16, right: 16, top: 16, bottom: 110 } },
    Column({ spacing: 16 }, [
        sectionTitle("Explorer"),
        card(Text("Ton contenu ici.", { color: T.muted }))
    ])
  )
}
''';

  static const _tabbedProfileTab = '''// Onglet Profil.
@use "../ui.ks"

fn profileTab() {
  return ScrollView({ padding: { left: 16, right: 16, top: 16, bottom: 110 } },
    Column({ spacing: 16 }, [
        sectionTitle("Profil"),
        card(Text("Réglages, compte, à-propos…", { color: T.muted }))
    ])
  )
}
''';

  // --- list-detail template -------------------------------------------------

  String _listDetailManifest(String projectName) => '''{
  "id": "$projectName",
  "name": "${_toTitleCase(projectName)}",
  "version": "1.0.0",
  "description": "A list-detail KromLang mini-app",
  "author": "",
  "entry": "list",
  "pages": {
    "list": {
      "name": "${_toTitleCase(projectName)}",
      "source": "pages/list.ks",
      "icon": "home"
    },
    "detail": {
      "name": "Détail",
      "source": "pages/detail.ks",
      "icon": "info"
    }
  },
  "permissions": []
}
''';

  static const _listData = '''// Données d'exemple — remplace par tes appels request(...) plus tard.
let ITEMS = [
  { id: 1, emoji: "🚀", title: "Premier article",  subtitle: "Commence ici" },
  { id: 2, emoji: "🎨", title: "Deuxième article", subtitle: "Un peu de couleur" },
  { id: 3, emoji: "⚡", title: "Troisième article", subtitle: "Toujours plus vite" }
]

// Pas de `else if` en KromScript : utilise else { if (...) { ... } }.
fn itemById(id) {
  let found = ITEMS[0]
  let rows = ITEMS.filter(fn(item) { return item.id == id })
  if (rows.length > 0) {
    found = rows[0]
  }
  return found
}
''';

  static const _listPage = '''// Liste : chaque ligne navigue vers la page détail avec son id (-> args).
@use "../utils/ui.ks"
@use "../utils/data.ks"

fn build() {
  let rows = ITEMS.map(fn(item) { return itemRow(item) })
  return Scaffold({ backgroundColor: T.bg, appBar: AppBar({ title: "Articles" }) },
    ScrollView({ padding: { left: 16, right: 16, top: 16, bottom: 24 } },
      Column({ spacing: 10, crossAxisAlignment: "stretch" }, rows)
    )
  )
}

fn itemRow(item) {
  return InkWell({ onTap: "openItem", arg: item.id, borderRadius: 16 },
    card(Row({ spacing: 12, crossAxisAlignment: "center" }, [
        Text(item.emoji, { fontSize: 24 }),
        Expanded({ flex: 1 }, Column({ spacing: 2 }, [
            Text(item.title, { fontWeight: "bold", color: T.text }),
            Text(item.subtitle, { fontSize: 12, color: T.muted })
        ])),
        Icon("chevron_right", { color: T.muted })
    ]))
  )
}

fn openItem(id) {
  nav.navigateTo("detail", { id: id })
}
''';

  static const _detailPage = '''// Détail : lit l'id passé par la liste via `args`.
@use "../utils/ui.ks"
@use "../utils/data.ks"

fn build() {
  // Pas de ternaire en KromScript — un simple if fait l'affaire.
  let itemId = 1
  if (args != null) {
    itemId = args.id
  }
  let item = itemById(itemId)
  return Scaffold({ backgroundColor: T.bg },
    ScrollView({ padding: { left: 16, right: 16, top: 16, bottom: 24 } },
      Column({ spacing: 16 }, [
          Row({ spacing: 10, crossAxisAlignment: "center" }, [
              IconButton("arrow_back", { onTap: "goBack" }),
              sectionTitle(item.title)
          ]),
          card(Column({ spacing: 8 }, [
              Text(item.emoji, { fontSize: 40 }),
              Text(item.subtitle, { color: T.muted })
          ]))
      ])
    )
  )
}

fn goBack() {
  nav.back()
}
''';

  // --- default template -----------------------------------------------------

  String _manifestTemplate(String projectName) => '''{
  "id": "$projectName",
  "name": "${_toTitleCase(projectName)}",
  "version": "1.0.0",
  "description": "A KromLang mini-app",
  "author": "",
  "entry": "home",
  "pages": {
    "home": {
      "name": "${_toTitleCase(projectName)}",
      "source": "pages/home.ks",
      "icon": "home"
    }
  },
  "permissions": []
}
''';

  static const _homePageTemplate = '''// Page d'accueil — thème de l'hôte (clair/sombre auto), compteur réactif.
@use "../utils/ui.ks"
@use "../components/app_button.ks"

let counter = Obs(0)

fn build() {
  return Scaffold({ backgroundColor: T.bg },
    ScrollView({ padding: { left: 20, right: 20, top: 28, bottom: 28 } },
      Column({ spacing: 18, crossAxisAlignment: "stretch" }, [
        sectionTitle("Bienvenue sur Krom 🚀"),
        Text("Édite pages/home.ks et enregistre : l'aperçu se recharge tout seul.",
             { color: T.muted, fontSize: 14 }),
        card(Column({ spacing: 14, crossAxisAlignment: "center" }, [
            Text("Compteur réactif", { color: T.muted, fontSize: 13 }),
            Obx({ builder: "counterValue" }),
            Row({ spacing: 12, mainAxisAlignment: "center" }, [
                AppButton("−", "onDecrement"),
                AppButton("+", "onIncrement")
            ])
        ]))
      ])
    )
  )
}

fn counterValue() {
  return Text("" + counter.value, { fontSize: 44, fontWeight: "bold", color: T.text })
}

fn onIncrement() { counter.set(counter.value + 1) }
fn onDecrement() { counter.set(counter.value - 1) }
''';

  static const _buttonComponentTemplate = '''// Composant bouton réutilisable, aligné sur le thème (T.primary).
// Nommé AppButton pour ne pas masquer le widget Button du cœur.
@use "../utils/ui.ks"

fn AppButton(label, onTap) {
  return InkWell({ onTap: onTap, borderRadius: 14 },
    Box({ color: T.primary, borderRadius: 14,
          padding: { left: 22, right: 22, top: 12, bottom: 12 } },
      Text(label, { fontSize: 18, fontWeight: "bold", color: "#FFFFFF" }))
  )
}
''';

  // --- form template --------------------------------------------------------

  static const _formPage = '''// Formulaire — champs, état réactif, résumé en direct, envoi.
@use "../utils/ui.ks"

let montant = Obs("")
let motif = Obs("Loyer")
let express = Obs(false)

fn build() {
  return Scaffold({ backgroundColor: T.bg, appBar: AppBar({ title: "Nouveau transfert" }) },
    ScrollView({ padding: { left: 20, right: 20, top: 20, bottom: 24 } },
      Column({ spacing: 18, crossAxisAlignment: "stretch" }, [
        TextField({ labelText: "Montant (F CFA)", value: montant.value,
                    onChange: "onMontant", keyboardType: "number", prefixIcon: "payment" }),
        Select({ label: "Motif", options: ["Loyer", "Courses", "Transport", "Autre"],
                 value: motif.value, onChange: "onMotif" }),
        card(Row({ mainAxisAlignment: "spaceBetween", crossAxisAlignment: "center" }, [
            Column({ spacing: 2, crossAxisAlignment: "start" }, [
                Text("Envoi express", { fontWeight: "bold", color: T.text }),
                Text("Reçu en quelques secondes", { fontSize: 12, color: T.muted })
            ]),
            Obx({ builder: "expressSwitch" })
        ])),
        Obx({ builder: "resume" }),
        Button("Envoyer", { onTap: "envoyer", color: T.primary, fullWidth: true, variant: "filled" })
      ])
    )
  )
}

fn expressSwitch() {
  return Switch({ value: express.value, onChanged: "toggleExpress", activeColor: T.primary })
}

fn resume() {
  let m = montant.value
  if (m == "") { m = "0" }
  // Pas de ternaire en KromScript côté runtime — un simple if fait l'affaire.
  let mode = "standard"
  if (express.value) { mode = "express" }
  return Text("Envoi de " + m + " F CFA — " + motif.value + " (" + mode + ")",
              { color: T.muted, fontSize: 13, textAlign: "center" })
}

fn onMontant(v) { montant.set(v) }
fn onMotif(v) { motif.set(v) }
fn toggleExpress(v) { express.set(v) }

fn envoyer() { print("Transfert: " + montant.value + " / " + motif.value) }
''';

  // --- dashboard template ---------------------------------------------------

  static const _dashboardPage = '''// Tableau de bord — cartes de stats, BarChart et Gauge.
@use "../utils/ui.ks"

fn statTile(label, valeur, teinte) {
  return Expanded({ flex: 1 },
    Box({ color: T.card, borderRadius: 16, padding: 16 },
      Column({ spacing: 6, crossAxisAlignment: "start" }, [
          Text(label, { fontSize: 12, color: T.muted }),
          Text(valeur, { fontSize: 22, fontWeight: "bold", color: teinte })
      ])))
}

fn build() {
  return Scaffold({ backgroundColor: T.bg, appBar: AppBar({ title: "Tableau de bord" }) },
    ScrollView({ padding: { left: 16, right: 16, top: 16, bottom: 24 } },
      Column({ spacing: 16, crossAxisAlignment: "stretch" }, [
        Row({ spacing: 12 }, [
            statTile("Entrées", "+ 58 000", T.primary),
            statTile("Sorties", "- 13 000", "#E24B4A")
        ]),
        card(Column({ spacing: 10, crossAxisAlignment: "stretch" }, [
            sectionTitle("Revenus par mois"),
            BarChart({ data: [
                { label: "Mar", value: 51000 },
                { label: "Avr", value: 47000 },
                { label: "Mai", value: 33000 },
                { label: "Jui", value: 58000 }
              ], height: 170, barColor: T.primary, highlightIndex: 3, valuePrefix: "F " })
        ])),
        card(Row({ spacing: 16, crossAxisAlignment: "center" }, [
            Gauge({ value: 0.62, size: 120, centerText: "62%", label: "du budget",
                    color: T.primary, danger: 0.9 }),
            Expanded({ flex: 1 },
              Column({ spacing: 6, crossAxisAlignment: "start" }, [
                  sectionTitle("Budget du mois"),
                  Text("62 % consommé sur 200 000 F CFA.", { color: T.muted, fontSize: 13 })
              ]))
        ]))
      ])
    )
  )
}
''';

  // --- onboarding template --------------------------------------------------

  static const _onboardingPage = '''// Onboarding — carrousel PageView avec points + bouton Commencer.
@use "../utils/ui.ks"

fn slide(emoji, titre, texte) {
  return Column({ spacing: 14, mainAxisAlignment: "center", crossAxisAlignment: "center" }, [
      Text(emoji, { fontSize: 64 }),
      Text(titre, { fontSize: 22, fontWeight: "bold", color: T.text, textAlign: "center" }),
      Box({ width: 260 },
        Text(texte, { fontSize: 14, color: T.muted, textAlign: "center" }))
  ])
}

fn slide1() { return slide("👋", "Bienvenue", "Ta mini-app Krom, prête à être personnalisée.") }
fn slide2() { return slide("⚡", "Ultra rapide", "Bundle à chaud et aperçu instantané sur ton téléphone.") }
fn slide3() { return slide("🚀", "Publie", "krom publish, puis lie ta mini-app à une super-app.") }

fn build() {
  return Scaffold({ backgroundColor: T.bg },
    Column({ spacing: 24, mainAxisAlignment: "center", crossAxisAlignment: "stretch" }, [
        PageView({ height: 360, showDots: true, activeDotColor: T.primary,
          pages: [ { builder: "slide1" }, { builder: "slide2" }, { builder: "slide3" } ]
        }),
        Box({ padding: { left: 24, right: 24 } },
          Button("Commencer", { onTap: "commencer", color: T.primary, fullWidth: true, variant: "filled" }))
    ])
  )
}

fn commencer() { print("Onboarding terminé") }
''';

  String _readmeTemplate(String projectName) =>
      '''# ${_toTitleCase(projectName)}

A KromLang mini-app.

## Getting Started

### Development

Start the dev server with hot reload:

```bash
krom dev
```

Then open http://localhost:3000 in your browser.

### Build

Build for production:

```bash
krom build
```

The bundled manifest will be in `dist/manifest.json`.

## Project Structure

```
$projectName/
├── manifest.json      # App configuration
├── pages/             # App pages (each has build() function)
├── components/        # Reusable components
├── utils/             # Utility functions
└── assets/            # Images and other assets
```

## Learn More

- [KromLang Documentation](https://github.com/dickode/krom-lang)
''';

  String _toTitleCase(String input) {
    return input
        .replaceAll(RegExp(r'[-_]'), ' ')
        .split(' ')
        .map((word) =>
            word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }
}
