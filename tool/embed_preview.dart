// Embeds the Flutter-web preview (krom_bundler_web) into the CLI as a generated
// Dart source file, so a distributed `krom` binary serves the preview from
// `krom dev` without a separate `make deploy-preview`.
//
// CanvasKit is loaded from the gstatic CDN at runtime (Flutter's default
// `--web-resources-cdn`), so the 26 MB local `canvaskit/` folder is NOT embedded
// — only the ~5 MB of JS/HTML/fonts the preview actually needs offline-of-CDN.
//
// Usage (from krom_bundler/):
//   dart run tool/embed_preview.dart [--source <build/web>] [--out <file>]
//
// Typically driven by `make embed-preview` in krom_bundler_web, which builds the
// web app first. See krom_bundler_web/Makefile.
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:path/path.dart' as p;

/// Files/dirs excluded from the embed: the CDN-served renderer, debug symbols,
/// legal text (not needed to render), and build-id scratch files.
bool _isExcluded(String rel) {
  if (rel.startsWith('canvaskit/')) return true; // served from the gstatic CDN
  if (rel.endsWith('.symbols')) return true; // debug symbol maps
  if (rel == 'assets/NOTICES') return true; // 1.3 MB of licences, unused
  if (rel == '.last_build_id') return true;
  // The dev server serves a no-op SW in place of this; embedding it is dead
  // weight and would only invite the cache/reload loop it causes.
  if (rel == 'flutter_service_worker.js') return true;
  return false;
}

Future<int> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('source',
        help: 'Path to the built Flutter web app (build/web).',
        defaultsTo: '../krom_bundler_web/build/web')
    ..addOption('out',
        help: 'Generated Dart file to write.',
        defaultsTo: 'lib/src/preview/preview_assets.g.dart')
    ..addFlag('help', abbr: 'h', negatable: false);

  final res = parser.parse(args);
  if (res['help'] as bool) {
    stdout.writeln('Embed the Flutter web preview into the CLI.\n');
    stdout.writeln(parser.usage);
    return 0;
  }

  final sourceDir = Directory(res['source'] as String);
  final outPath = res['out'] as String;

  if (!sourceDir.existsSync()) {
    stderr.writeln('✗ Preview build not found: ${sourceDir.path}');
    stderr.writeln('  Build it first: (cd krom_bundler_web && '
        'flutter build web --no-tree-shake-icons)');
    return 1;
  }

  final buildId = _readBuildId(sourceDir);

  // Deterministic order so the generated file diffs cleanly across runs.
  final files = sourceDir
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => p.posix.joinAll(p.split(p.relative(f.path, from: sourceDir.path))))
      .where((rel) => !_isExcluded(rel))
      .toList()
    ..sort();

  if (files.isEmpty) {
    stderr.writeln('✗ No embeddable files under ${sourceDir.path}');
    return 1;
  }

  final buf = StringBuffer()
    ..writeln('// GENERATED FILE — do not edit by hand.')
    ..writeln('//')
    ..writeln('// Regenerate: (cd krom_bundler_web && make embed-preview)')
    ..writeln('// or: dart run tool/embed_preview.dart --source '
        '<krom_bundler_web/build/web>')
    ..writeln('//')
    ..writeln('// CanvasKit is served from the gstatic CDN at runtime and is not')
    ..writeln('// embedded here. Values are gzip-compressed, base64-encoded bytes.')
    ..writeln('// dart format off')
    ..writeln("// ignore_for_file: type=lint")
    ..writeln()
    ..writeln("const String kEmbeddedPreviewBuildId = '$buildId';")
    ..writeln('const int kEmbeddedPreviewFileCount = ${files.length};')
    ..writeln()
    ..writeln('/// Web-preview files, path -> base64(gzip(bytes)).')
    ..writeln('const Map<String, String> kEmbeddedPreviewGz = {');

  var rawTotal = 0;
  var gzTotal = 0;
  for (final rel in files) {
    final bytes = File(p.join(sourceDir.path, rel)).readAsBytesSync();
    final gz = gzip.encode(bytes); // GZipCodec, default level
    final b64 = base64.encode(gz);
    rawTotal += bytes.length;
    gzTotal += gz.length;
    buf.writeln("  '$rel':");
    buf.writeln("      '$b64',");
  }
  buf.writeln('};');

  final outFile = File(outPath);
  outFile.parent.createSync(recursive: true);
  outFile.writeAsStringSync(buf.toString());

  String mb(int n) => '${(n / (1024 * 1024)).toStringAsFixed(2)} MB';
  stdout.writeln('✓ Embedded ${files.length} files into $outPath');
  stdout.writeln('  build id : $buildId');
  stdout.writeln('  raw      : ${mb(rawTotal)}');
  stdout.writeln('  gzipped  : ${mb(gzTotal)} (base64 source ~${mb((gzTotal * 4) ~/ 3)})');
  return 0;
}

String _readBuildId(Directory sourceDir) {
  final f = File(p.join(sourceDir.path, '.last_build_id'));
  if (f.existsSync()) return f.readAsStringSync().trim();
  return DateTime.now().toUtc().toIso8601String();
}
