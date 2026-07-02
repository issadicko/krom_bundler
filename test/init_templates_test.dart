import 'dart:convert';
import 'dart:io';

import 'package:krom_bundler/src/bundler/manifest_bundler.dart';
import 'package:krom_bundler/src/commands/init_command.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Every `krom init --template X` scaffold must survive the FULL bundler
/// (parse, validation, tree-shaking) — a template that doesn't compile is a
/// broken first impression.
void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('init_templates'));
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<Map<String, dynamic>> scaffoldAndBundle(String template) async {
    final files = InitCommand().templateFiles(template, 'myapp');
    for (final entry in files.entries) {
      final file = File(p.join(tmp.path, entry.key));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(entry.value);
    }
    final bundled = await ManifestBundler()
        .bundleProject(p.join(tmp.path, 'manifest.json'));
    return jsonDecode(bundled) as Map<String, dynamic>;
  }

  test('default template bundles', () async {
    final bundle = await scaffoldAndBundle('default');
    expect(bundle['id'], 'myapp');
    expect(bundle['pages'], contains('home'));
  });

  test('tabbed template bundles and keeps every tab builder', () async {
    final bundle = await scaffoldAndBundle('tabbed');
    final home = (bundle['pages'] as Map)['home'] as Map;
    final source = home['script'] as String;
    // The optimizer must keep the string-referenced tab builders.
    for (final builder in ['homeTab', 'exploreTab', 'profileTab', 'counterValue']) {
      expect(source, contains('fn $builder'),
          reason: 'tree-shaker dropped $builder');
    }
  });

  test('list-detail template bundles both pages', () async {
    final bundle = await scaffoldAndBundle('list-detail');
    final pages = bundle['pages'] as Map;
    expect(pages.keys, containsAll(['list', 'detail']));
    expect((pages['list'] as Map)['script'], contains('fn openItem'));
    expect((pages['detail'] as Map)['script'], contains('fn goBack'));
  });
}
