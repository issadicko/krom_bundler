// Embeds the domain libs' `krom_lib.json` descriptors into the CLI as generated
// Dart, so `krom build` / `krom dev` know their components and modules without
// the developer installing or fetching anything.
//
// That knowledge is what makes a lib feel like core to the tooling: a
// `LineChart` validates, a `charts.palette(...)` call validates, and using
// either without declaring its pack produces a named, actionable error instead
// of "undefined variable".
//
// Usage (from krom_bundler/):
//   dart run tool/embed_lib_descriptors.dart [--libs <dir>] [--out <file>]
//
// `--libs` defaults to the parent directory holding the krom_lib_* repos.
// Re-run whenever a lib adds or renames a component, a module, or a method.
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

/// The libs bundled with the CLI, in the order they appear in the generated map.
const _libDirs = [
  'krom_lib_charts',
  'krom_lib_media',
  'krom_lib_forms',
  'krom_lib_sensors',
];

void main(List<String> args) {
  final parser = ArgParser()
    ..addOption('libs', help: 'Directory containing the krom_lib_* repos.')
    ..addOption('out', help: 'Generated Dart file to write.');
  final opts = parser.parse(args);

  final libsRoot = opts['libs'] as String? ?? p.normalize(p.join(p.current, '..'));
  final outPath = opts['out'] as String? ??
      p.join(p.current, 'lib', 'src', 'libs', 'lib_descriptors.g.dart');

  final packs = <String, Map<String, dynamic>>{};

  for (final dir in _libDirs) {
    final file = File(p.join(libsRoot, dir, 'krom_lib.json'));
    if (!file.existsSync()) {
      stderr.writeln('✗ descripteur introuvable : ${file.path}');
      exit(1);
    }
    final Map<String, dynamic> descriptor =
        jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;

    final pack = descriptor['pack'] as String;
    final components = ((descriptor['components'] as List?) ?? const [])
        .map((c) => (c as Map)['name'] as String)
        .toList()
      ..sort();
    final modules = <String, List<String>>{};
    for (final m in (descriptor['modules'] as List?) ?? const []) {
      final module = m as Map;
      modules[module['name'] as String] =
          ((module['methods'] as List?) ?? const [])
              .map((x) => (x as Map)['name'] as String)
              .toList()
            ..sort();
    }

    packs[pack] = {
      'version': descriptor['version'],
      'components': components,
      'modules': modules,
    };
    stdout.writeln(
      '  $pack ${descriptor['version']} — '
      '${components.length} composants, ${modules.length} module(s)',
    );
  }

  final buffer = StringBuffer()
    ..writeln('// GENERATED — ne pas éditer à la main.')
    ..writeln('// Source : krom_lib_*/krom_lib.json')
    ..writeln('// Régénérer : dart run tool/embed_lib_descriptors.dart')
    ..writeln()
    ..writeln('/// Les composants et modules de chaque lib de domaine embarquée,')
    ..writeln('/// indexés par pack de capacité.')
    ..writeln('const Map<String, KromLibDescriptor> kKromLibDescriptors = {');

  packs.forEach((pack, data) {
    final components =
        (data['components'] as List<String>).map((c) => "'$c'").join(', ');
    final modules = (data['modules'] as Map<String, List<String>>)
        .entries
        .map((e) => "'${e.key}': [${e.value.map((m) => "'$m'").join(', ')}]")
        .join(', ');
    buffer
      ..writeln("  '$pack': KromLibDescriptor(")
      ..writeln("    pack: '$pack',")
      ..writeln("    version: '${data['version']}',")
      ..writeln('    components: [$components],')
      ..writeln('    modules: {$modules},')
      ..writeln('  ),');
  });

  buffer
    ..writeln('};')
    ..writeln()
    ..writeln('/// Ce qu\'une lib de domaine expose au script d\'une mini-app.')
    ..writeln('class KromLibDescriptor {')
    ..writeln('  const KromLibDescriptor({')
    ..writeln('    required this.pack,')
    ..writeln('    required this.version,')
    ..writeln('    required this.components,')
    ..writeln('    required this.modules,')
    ..writeln('  });')
    ..writeln()
    ..writeln('  /// Le pack déclaré dans le `requires` du manifeste.')
    ..writeln('  final String pack;')
    ..writeln()
    ..writeln('  /// Version de la lib dont ce descripteur a été extrait.')
    ..writeln('  final String version;')
    ..writeln()
    ..writeln('  /// Noms des composants, utilisables comme des widgets.')
    ..writeln('  final List<String> components;')
    ..writeln()
    ..writeln('  /// Namespaces exposés, et les méthodes de chacun.')
    ..writeln('  final Map<String, List<String>> modules;')
    ..writeln('}');

  final out = File(outPath)..createSync(recursive: true);
  out.writeAsStringSync(buffer.toString());
  stdout.writeln('✓ ${packs.length} packs embarqués dans $outPath');
}
