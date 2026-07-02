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
          allowed: ['default', 'tabbed', 'list-detail'],
          allowedHelp: {
            'default': 'Single page with a counter and a reusable component.',
            'tabbed': 'Floating tab bar (TabHostNav), one component per tab.',
            'list-detail': 'A list page navigating to a detail page (args).',
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
      default:
        return {
          'manifest.json': _manifestTemplate(projectName),
          'pages/home.ks': _homePageTemplate,
          'components/app_button.ks': _buttonComponentTemplate,
          'utils/helpers.ks': _helpersTemplate,
        };
    }
  }

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
        showLabels: false,
        backgroundColor: T.card,
        selectedColor: T.text,
        unselectedColor: T.muted,
        tabs: [
          { icon: "home",   builder: "homeTab" },
          { icon: "store",  builder: "exploreTab" },
          { icon: "person", builder: "profileTab" }
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
    Column({ spacing: 16 }, [
        sectionTitle("Bienvenue 👋"),
        card(Column({ spacing: 10 }, [
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
  return Scaffold({ backgroundColor: T.bg },
    ScrollView({ padding: { left: 16, right: 16, top: 16, bottom: 24 } },
      Column({ spacing: 12 }, [
          sectionTitle("Articles"),
          Column({ spacing: 10 }, rows)
      ])
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
      "name": "Home",
      "source": "pages/home.ks",
      "icon": "home"
    }
  },
  
  "utils": [
    "utils/helpers.ks"
  ],
  
  "permissions": []
}
''';

  static const _homePageTemplate = '''// Home page
@use "../components/app_button"

let counter = Obs(0)

fn build() {
  return Box({ color: "#f5f5f5", height: "infinity", width: "infinity" }, [
    Column({ spacing: 24, mainAxisAlignment: "center", crossAxisAlignment: "center" }, [
      Text("Welcome to KromLang! 🚀", { 
        fontSize: 24, 
        fontWeight: "bold", 
        color: "#333" 
      }),
      
      Obx({ builder: "counterBuilder" }),
      
      Row({ spacing: 12 }, [
        AppButton("Increment", "#4CAF50", "onIncrement"),
        AppButton("Decrement", "#f44336", "onDecrement")
      ])
    ])
  ])
}

fn counterBuilder() {
  return Text("Count: " + counter.value, { 
    fontSize: 48, 
    fontWeight: "bold", 
    color: "#333" 
  })
}

fn onIncrement() {
  counter.set(counter.value + 1)
}

fn onDecrement() {
  counter.set(counter.value - 1)
}
''';

  static const _buttonComponentTemplate = '''// Reusable button component
// Named AppButton to avoid conflict with core Button widget
fn AppButton(label, color, onTap) {
  return InkWell({ onTap: onTap, borderRadius: 8 }, [
    Box({ 
      padding: 16, 
      borderRadius: 8, 
      color: color 
    }, [
      Text(label, { 
        fontSize: 16, 
        fontWeight: "bold", 
        color: "white" 
      })
    ])
  ])
}
''';

  static const _helpersTemplate = '''// Utility functions

fn formatNumber(num) {
  return num
}

fn clamp(value, min, max) {
  if (value < min) { return min }
  if (value > max) { return max }
  return value
}
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
