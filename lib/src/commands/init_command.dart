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
    argParser.addFlag('link',
        defaultsTo: true,
        help: 'Also create the app on the backend (when connected) and write '
            'its "appId" into the manifest.');
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

    try {
      // Create directories
      Logger.step(1, 4, 'Creating project structure...');
      await Directory(p.join(projectName, 'pages')).create(recursive: true);
      await Directory(p.join(projectName, 'components'))
          .create(recursive: true);
      await Directory(p.join(projectName, 'utils')).create(recursive: true);
      await Directory(p.join(projectName, 'assets', 'images'))
          .create(recursive: true);

      // Create manifest.json
      Logger.step(2, 4, 'Generating manifest.json...');
      await File(p.join(projectName, 'manifest.json'))
          .writeAsString(_manifestTemplate(projectName));

      // Create example files
      Logger.step(3, 4, 'Creating example files...');
      await File(p.join(projectName, 'pages', 'home.ks'))
          .writeAsString(_homePageTemplate);
      await File(p.join(projectName, 'components', 'app_button.ks'))
          .writeAsString(_buttonComponentTemplate);
      await File(p.join(projectName, 'utils', 'helpers.ks'))
          .writeAsString(_helpersTemplate);

      // Create README
      Logger.step(4, 4, 'Creating README...');
      await File(p.join(projectName, 'README.md'))
          .writeAsString(_readmeTemplate(projectName));

      Logger.newline();
      Logger.success('Project "$projectName" created!');
      Logger.newline();
      Logger.fileCreated('$projectName/manifest.json');
      Logger.fileCreated('$projectName/pages/home.ks');
      Logger.fileCreated('$projectName/components/app_button.ks');
      Logger.fileCreated('$projectName/utils/helpers.ks');
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
