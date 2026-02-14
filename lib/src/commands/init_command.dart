import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

/// Init command - creates a new mini-app project
class InitCommand extends Command<int> {
  @override
  final name = 'init';

  @override
  final description = 'Create a new KromLang mini-app project';

  @override
  String get invocation => 'krom init <project_name>';

  @override
  Future<int> run() async {
    if (argResults!.rest.isEmpty) {
      print('❌ Missing project name');
      print('Usage: krom init <project_name>');
      return 1;
    }

    final projectName = argResults!.rest.first;
    final projectDir = Directory(projectName);

    if (await projectDir.exists()) {
      print('❌ Directory "$projectName" already exists');
      return 1;
    }

    print('🚀 Creating mini-app: $projectName');

    try {
      // Create directories
      await Directory(p.join(projectName, 'pages')).create(recursive: true);
      await Directory(p.join(projectName, 'components')).create(recursive: true);
      await Directory(p.join(projectName, 'utils')).create(recursive: true);
      await Directory(p.join(projectName, 'assets', 'images')).create(recursive: true);

      // Create manifest.json
      await File(p.join(projectName, 'manifest.json')).writeAsString(_manifestTemplate(projectName));

      // Create example files
      await File(p.join(projectName, 'pages', 'home.ks')).writeAsString(_homePageTemplate);
      await File(p.join(projectName, 'components', 'button.ks')).writeAsString(_buttonComponentTemplate);
      await File(p.join(projectName, 'utils', 'helpers.ks')).writeAsString(_helpersTemplate);

      // Create README
      await File(p.join(projectName, 'README.md')).writeAsString(_readmeTemplate(projectName));

      print('');
      print('✅ Project "$projectName" created successfully!');
      print('');
      print('   📁 $projectName/');
      print('   ├── manifest.json');
      print('   ├── pages/');
      print('   │   └── home.ks');
      print('   ├── components/');
      print('   │   └── button.ks');
      print('   ├── utils/');
      print('   │   └── helpers.ks');
      print('   └── assets/images/');
      print('');
      print('Next steps:');
      print('   cd $projectName');
      print('   krom dev');
      print('');

      return 0;
    } catch (e) {
      print('❌ Failed to create project: $e');
      return 1;
    }
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
  
  "components": {
    "Button": {
      "name": "Button",
      "source": "components/button.ks"
    }
  },
  
  "utils": [
    "utils/helpers.ks"
  ],
  
  "permissions": []
}
''';

  static const _homePageTemplate = '''// Home page
@use "../components/button"

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
        Button("Increment", "#4CAF50", "onIncrement"),
        Button("Decrement", "#f44336", "onDecrement")
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

  static const _buttonComponentTemplate = '''// Reusable Button component
fn Button(label, color, onTap) {
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

  String _readmeTemplate(String projectName) => '''# ${_toTitleCase(projectName)}

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
        .map((word) => word.isEmpty ? '' : '${word[0].toUpperCase()}${word.substring(1)}')
        .join(' ');
  }
}
