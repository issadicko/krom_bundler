import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'bundler.dart';

/// One embedded asset: its project-relative path plus integrity metadata.
///
/// [relPath] is always POSIX-style (forward slashes) so the package layout is
/// stable across platforms and matches the paths used inside `app.json`
/// (`icon`, `tabBar.iconPath`, page assets, …).
class PackagedAsset {
  /// Project-relative path, POSIX-style (e.g. `assets/icon.png`).
  final String relPath;

  /// Raw bytes of the asset on disk.
  final List<int> bytes;

  /// Lowercase hex SHA-256 of [bytes].
  final String sha256Hex;

  /// Size of [bytes] in bytes.
  final int size;

  PackagedAsset({
    required this.relPath,
    required this.bytes,
    required this.sha256Hex,
    required this.size,
  });
}

/// The result of building a signed-ready version package.
///
/// The actual signature is produced by the backend; this only carries the
/// ZIP bytes, the asset integrity map, and the package's own SHA-256.
class PackageResult {
  /// Raw bytes of the `<appId>__<version>.zip` archive.
  final List<int> zipBytes;

  /// Lowercase hex SHA-256 of [zipBytes] (package integrity).
  final String zipSha256Hex;

  /// The embedded assets, in deterministic (sorted) order.
  final List<PackagedAsset> assets;

  /// The final `app.json` content (compiled manifest + `assets` integrity map),
  /// pretty-printed unless [minified].
  final String appJson;

  PackageResult({
    required this.zipBytes,
    required this.zipSha256Hex,
    required this.assets,
    required this.appJson,
  });
}

/// Builds the signed-ready version **package** for a mini-app: a ZIP laid out
/// as
///
/// ```
/// app.json            # compiled manifest + "assets" integrity map
/// assets/<relPath>    # raw asset bytes (png/jpg/svg/icons/fonts)
/// ```
///
/// where `app.json.assets` is `{ "<relPath>": { "sha256": "<hex>",
/// "size": <int> }, … }` for every embedded asset. Package integrity is the
/// SHA-256 of the ZIP's bytes; the cryptographic signature is added later by
/// the backend.
///
/// Asset discovery is intentionally conservative: a manifest reference (e.g.
/// `tabBar.iconPath`, the top-level `icon`, or a page `icon`) is treated as an
/// asset only when a matching file exists on disk. This lets Material-style
/// icon *names* (`bar_chart`, `account_balance_wallet`, …) pass through
/// untouched while real files are collected and hashed. Everything under the
/// project's `assets/` directory is always included.
class AssetPackager {
  /// Project-relative directory that is always swept for assets.
  static const assetsDirName = 'assets';

  /// Build the package for [compiledManifest] (the bundler's `app.json`
  /// object, already containing compiled scripts).
  ///
  /// [projectDir] is the directory that holds `manifest.json`; all asset
  /// paths are resolved relative to it. The returned [PackageResult.appJson]
  /// is the manifest with an added `assets` integrity map.
  ///
  /// Throws [BundlerException] if a manifest-referenced asset path looks like a
  /// file (has an extension or a path separator) but is missing on disk.
  static Future<PackageResult> build({
    required Map<String, dynamic> compiledManifest,
    required String projectDir,
    bool minify = false,
  }) async {
    final assets = await _collectAssets(compiledManifest, projectDir);

    // Build the integrity map keyed by project-relative POSIX path.
    final integrity = <String, dynamic>{};
    for (final a in assets) {
      integrity[a.relPath] = {'sha256': a.sha256Hex, 'size': a.size};
    }

    // app.json = compiled manifest + assets integrity map. We copy so we never
    // mutate the caller's manifest, and only attach `assets` when non-empty to
    // keep asset-free packages byte-identical to the plain manifest + key.
    final appManifest = Map<String, dynamic>.from(compiledManifest);
    if (integrity.isNotEmpty) {
      appManifest['assets'] = integrity;
    }

    final encoder =
        minify ? const JsonEncoder() : const JsonEncoder.withIndent('  ');
    final appJson = encoder.convert(appManifest);

    // Assemble the ZIP: app.json at the root, raw bytes under assets/<relPath>.
    // Encode app.json to UTF-8 bytes explicitly. ArchiveFile.string records the
    // string's code-unit length as the entry size, which differs from the
    // UTF-8 byte length whenever the JSON contains non-ASCII characters
    // (accents, ellipsis, emoji) — producing an entry whose declared size is
    // smaller than its data and which strict ZIP readers (e.g. Java's
    // ZipInputStream, used by the backend) reject with "invalid entry size".
    final appJsonBytes = utf8.encode(appJson);
    final archive = Archive()
      ..addFile(
        ArchiveFile('app.json', appJsonBytes.length, appJsonBytes),
      );
    for (final a in assets) {
      archive.addFile(ArchiveFile(a.relPath, a.size, a.bytes));
    }

    final zipBytes = ZipEncoder().encode(archive) ?? const <int>[];
    final zipSha = sha256.convert(zipBytes).toString();

    return PackageResult(
      zipBytes: zipBytes,
      zipSha256Hex: zipSha,
      assets: assets,
      appJson: appJson,
    );
  }

  /// The canonical package file name for [appId] at [version]:
  /// `<appId>__<version>.zip`.
  static String packageFileName(String appId, String version) =>
      '${appId}__$version.zip';

  // --- internals ------------------------------------------------------------

  /// Collect every embedded asset for [manifest], de-duplicated and sorted by
  /// relative path for deterministic archives.
  static Future<List<PackagedAsset>> _collectAssets(
    Map<String, dynamic> manifest,
    String projectDir,
  ) async {
    // relPath (POSIX) -> absolute file, de-duplicated.
    final found = <String, File>{};

    // 1. Sweep the whole assets/ directory if present.
    final assetsDir = Directory(p.join(projectDir, assetsDirName));
    if (assetsDir.existsSync()) {
      await for (final entity in assetsDir.list(recursive: true)) {
        if (entity is File) {
          final rel = _toPosix(p.relative(entity.path, from: projectDir));
          found[rel] = entity;
        }
      }
    }

    // 2. Add explicit manifest references (icons, tabBar icons, page assets).
    final missing = <String>[];
    for (final ref in _manifestAssetRefs(manifest)) {
      final rel = _toPosix(ref);
      if (found.containsKey(rel)) continue;

      final file = File(p.join(projectDir, rel));
      if (file.existsSync()) {
        found[rel] = file;
      } else if (_looksLikeFile(rel)) {
        // Has an extension or a path separator => the author meant a file.
        missing.add(rel);
      }
      // Otherwise it's a bare token (Material icon name): not an asset.
    }

    if (missing.isNotEmpty) {
      final bullets = missing.map((m) => '  - $m').join('\n');
      throw BundlerException(
        'Referenced asset${missing.length == 1 ? '' : 's'} missing on disk '
        '(${missing.length}):\n$bullets\n'
        'Place the file(s) under the project directory or fix the path in '
        'manifest.json.',
      );
    }

    final relPaths = found.keys.toList()..sort();
    final assets = <PackagedAsset>[];
    for (final rel in relPaths) {
      final bytes = await found[rel]!.readAsBytes();
      assets.add(PackagedAsset(
        relPath: rel,
        bytes: bytes,
        sha256Hex: sha256.convert(bytes).toString(),
        size: bytes.length,
      ));
    }
    return assets;
  }

  /// Pull every candidate asset reference out of [manifest]:
  /// the top-level `icon`, each `tabBar.list[].iconPath`, each page `icon`,
  /// and each page's `assets` list (if the author declared one).
  static Iterable<String> _manifestAssetRefs(Map<String, dynamic> manifest) {
    final refs = <String>[];

    final icon = manifest['icon'];
    if (icon is String && icon.isNotEmpty) refs.add(icon);

    final tabBar = manifest['tabBar'];
    if (tabBar is Map) {
      final list = tabBar['list'];
      if (list is List) {
        for (final item in list) {
          if (item is Map) {
            final iconPath = item['iconPath'];
            if (iconPath is String && iconPath.isNotEmpty) refs.add(iconPath);
            final selected = item['selectedIconPath'];
            if (selected is String && selected.isNotEmpty) refs.add(selected);
          }
        }
      }
    }

    final pages = manifest['pages'];
    if (pages is Map) {
      for (final page in pages.values) {
        if (page is Map) {
          _addPageAssetRefs(page, refs);
        }
      }
    }

    // Subpackage pages carry the same shape as top-level pages.
    final subpackages = manifest['subpackages'];
    if (subpackages is List) {
      for (final pkg in subpackages) {
        if (pkg is Map && pkg['pages'] is Map) {
          for (final page in (pkg['pages'] as Map).values) {
            if (page is Map) _addPageAssetRefs(page, refs);
          }
        }
      }
    }

    return refs;
  }

  static void _addPageAssetRefs(Map page, List<String> refs) {
    final pageIcon = page['icon'];
    if (pageIcon is String && pageIcon.isNotEmpty) refs.add(pageIcon);
    final pageAssets = page['assets'];
    if (pageAssets is List) {
      for (final a in pageAssets) {
        if (a is String && a.isNotEmpty) refs.add(a);
      }
    }
  }

  /// A reference "looks like a file" — and so a missing one is an error —
  /// when it has a path separator or a file extension. Bare tokens such as
  /// `bar_chart` (Material icon names) are not treated as files.
  static bool _looksLikeFile(String ref) {
    if (ref.contains('/') || ref.contains('\\')) return true;
    return p.extension(ref).isNotEmpty;
  }

  static String _toPosix(String path) => p.posix.joinAll(p.split(path));
}
