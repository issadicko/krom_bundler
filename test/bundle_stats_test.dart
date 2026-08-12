import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:krom_bundler/src/bundler/manifest_bundler.dart';

/// Trois pages, `utils/ui.ks` importé par les trois : la forme qui duplique.
Directory _project() {
  final dir = Directory.systemTemp.createTempSync('krom_stats_');
  addTearDown(() => dir.deleteSync(recursive: true));

  Directory(p.join(dir.path, 'utils')).createSync();
  Directory(p.join(dir.path, 'pages')).createSync();

  File(p.join(dir.path, 'utils', 'ui.ks')).writeAsStringSync(
    'let T = { bg: "#FFF", text: "#000", accent: "#F60" }\n'
    'fn card(child) { return Box({ color: T.bg }, child) }\n',
  );
  File(p.join(dir.path, 'utils', 'data.ks'))
      .writeAsStringSync('let ROWS = [1, 2, 3]\n');

  for (final page in ['home', 'detail']) {
    File(p.join(dir.path, 'pages', '$page.ks')).writeAsStringSync(
      '@use "../utils/ui.ks"\n'
      '@use "../utils/data.ks"\n'
      'fn build() { return card(Text("$page")) }\n',
    );
  }
  File(p.join(dir.path, 'pages', 'solo.ks')).writeAsStringSync(
    '@use "../utils/ui.ks"\n'
    'fn build() { return card(Text("solo")) }\n',
  );

  File(p.join(dir.path, 'manifest.json')).writeAsStringSync('''
{
  "id": "stats", "name": "Stats", "version": "1.0.0", "entry": "home",
  "pages": {
    "home":   { "name": "Accueil", "source": "pages/home.ks" },
    "detail": { "name": "Détail",  "source": "pages/detail.ks" },
    "solo":   { "name": "Solo",    "source": "pages/solo.ks" }
  }
}
''');
  return dir;
}

void main() {
  group('BundleStats', () {
    test('compte les copies de chaque module partagé', () async {
      final dir = _project();
      final bundler = ManifestBundler();
      await bundler.bundleProjectToMap(p.join(dir.path, 'manifest.json'));

      final rows = {
        for (final row in bundler.stats.duplicated)
          p.basename(row.path): row.copies
      };
      expect(rows['ui.ks'], 3);
      expect(rows['data.ks'], 2);
      // Une page n'est jamais sa propre duplication.
      expect(rows.containsKey('home.ks'), isFalse);
    });

    test('classe du plus coûteux au moins coûteux', () async {
      final dir = _project();
      final bundler = ManifestBundler();
      await bundler.bundleProjectToMap(p.join(dir.path, 'manifest.json'));

      final wasted = bundler.stats.duplicated.map((r) => r.wasted).toList();
      expect(wasted, equals([...wasted]..sort((a, b) => b.compareTo(a))));
      expect(bundler.stats.duplicated.first.path, endsWith('ui.ks'));
    });

    test('le rapport nomme les modules et conclut', () async {
      final dir = _project();
      final bundler = ManifestBundler();
      await bundler.bundleProjectToMap(p.join(dir.path, 'manifest.json'));

      final report = bundler.stats.report();
      expect(report, contains('utils/ui.ks'));
      expect(report, contains('× 3'));
      expect(report, contains('gzip'));
      // Sur un projet de cette taille, gzip absorbe la redite : le rapport doit
      // le dire, pas laisser croire à un gain.
      expect(report, contains('La compression absorbe déjà la redite'));
      expect(report, contains('réévalué à chaque ouverture'));
    });

    test('un projet sans module partagé le dit', () async {
      final dir = Directory.systemTemp.createTempSync('krom_stats_solo_');
      addTearDown(() => dir.deleteSync(recursive: true));
      Directory(p.join(dir.path, 'pages')).createSync();
      File(p.join(dir.path, 'pages', 'home.ks'))
          .writeAsStringSync('fn build() { return Text("seul") }\n');
      File(p.join(dir.path, 'manifest.json')).writeAsStringSync('''
{
  "id": "solo", "name": "Solo", "version": "1.0.0", "entry": "home",
  "pages": { "home": { "name": "Accueil", "source": "pages/home.ks" } }
}
''');

      final bundler = ManifestBundler();
      await bundler.bundleProjectToMap(p.join(dir.path, 'manifest.json'));

      expect(bundler.stats.duplicated, isEmpty);
      expect(bundler.stats.report(), contains('Aucun module partagé'));
    });
  });
}
