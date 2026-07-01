import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Disposable per-project cache at `.krom/project.json` (next to the
/// manifest): last resolved bindings, last published version — display-only
/// state for the extension's status bar and offline listings.
///
/// Identity lives in the manifest (`appId`), and the backend stays the source
/// of truth for bindings — losing this file costs nothing. `.krom/` therefore
/// self-gitignores (a `.gitignore` containing `*` is written alongside).
class ProjectCache {
  ProjectCache(this.projectDir);

  final String projectDir;

  File get _file => File(p.join(projectDir, '.krom', 'project.json'));

  Map<String, dynamic> read() {
    try {
      return jsonDecode(_file.readAsStringSync()) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Merges [patch] into the cached state (null values delete keys).
  void update(Map<String, dynamic> patch) {
    final data = read();
    for (final e in patch.entries) {
      if (e.value == null) {
        data.remove(e.key);
      } else {
        data[e.key] = e.value;
      }
    }
    final dir = _file.parent..createSync(recursive: true);
    final gitignore = File(p.join(dir.path, '.gitignore'));
    if (!gitignore.existsSync()) gitignore.writeAsStringSync('*\n');
    _file.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(data)}\n');
  }

  void recordPublish({required String appId, required String version}) =>
      update({
        'appId': appId,
        'lastPublished': version,
        'publishedAt': DateTime.now().toUtc().toIso8601String(),
      });

  /// Replaces the cached bindings list ([bindings] items: `superAppId`,
  /// `name`, `isActive`).
  void recordBindings({
    required String appId,
    required List<Map<String, dynamic>> bindings,
  }) =>
      update({
        'appId': appId,
        'bindings': bindings,
        'bindingsSyncedAt': DateTime.now().toUtc().toIso8601String(),
      });
}
