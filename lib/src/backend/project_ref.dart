import 'dart:convert';
import 'dart:io';

import '../utils/logger.dart';
import 'backend_client.dart';

/// The project identity carried by `manifest.json`: the URL-friendly slug
/// (`id`) plus, once linked, the backend UUID (`appId`).
///
/// The manifest is the single committed source of identity — `krom init`
/// (connected) and `krom link` write `appId` right after `id`, so a fresh
/// `git clone` is fully linked with no local state. `.krom/project.json` is
/// only a disposable cache on top of this.
class ManifestRef {
  ManifestRef._(this.path, this._json);

  final String path;
  final Map<String, dynamic> _json;

  static ManifestRef load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw const FileSystemException('Manifest not found');
    }
    final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    return ManifestRef._(path, json);
  }

  String? get slug {
    final v = _json['id']?.toString();
    return (v == null || v.isEmpty) ? null : v;
  }

  /// The backend UUID, or null when the project was never linked (or the
  /// value doesn't look like a UUID — a hand-edited manifest shouldn't be
  /// able to send us to a bogus endpoint).
  String? get appId {
    final v = _json['appId']?.toString();
    return (v != null && looksLikeUuid(v)) ? v : null;
  }

  String? get name => _json['name']?.toString();
  String? get description => _json['description']?.toString();
  String get version => _json['version']?.toString() ?? '0.0.0';

  String get projectDir => File(path).parent.path;

  /// Writes [appId] into the manifest, inserted right after `id` (or updated
  /// in place), preserving the key order of the file.
  void writeAppId(String appId) {
    if (_json.containsKey('appId')) {
      _json['appId'] = appId;
    } else {
      final entries = _json.entries.toList();
      _json.clear();
      for (final e in entries) {
        _json[e.key] = e.value;
        if (e.key == 'id') _json['appId'] = appId;
      }
      _json.putIfAbsent('appId', () => appId);
    }
    File(path).writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(_json)}\n');
  }

  static final _uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');
  static bool looksLikeUuid(String v) => _uuid.hasMatch(v);
}

/// Resolves the backend app for [manifest], self-healing the committed
/// `appId`:
///
/// 1. A manifest `appId` is trusted first (one `GET /apps/{id}`).
/// 2. When it is absent or stale — the backend answers 404 for unknown ids
///    AND for apps of other tenants — fall back to the slug: find (and with
///    [createIfMissing], create) the app, then write the fresh UUID back into
///    the manifest so the next run hits rule 1.
///
/// Returns null only when the app doesn't exist and [createIfMissing] is
/// false. Network/auth failures bubble up as [BackendException].
Future<BackendApp?> resolveProjectApp({
  required BackendClient client,
  required ManifestRef manifest,
  bool createIfMissing = true,
}) async {
  final slug = manifest.slug;
  if (slug == null) {
    throw BackendException('manifest.json has no "id" (the app slug).');
  }

  final declared = manifest.appId;
  if (declared != null) {
    final app = await client.getApp(declared);
    if (app != null) return app;
    Logger.warn('appId $declared is unknown to this backend — '
        're-linking via slug "$slug".');
  }

  final bySlug = await client.findAppBySlug(slug);
  BackendApp? app = bySlug;
  if (app == null) {
    if (!createIfMissing) return null;
    app = await client.createApp(
      name: manifest.name ?? slug,
      slug: slug,
      description: manifest.description,
    );
    Logger.success('Created app "$slug" on the backend (${app.id}).');
  }

  if (declared != app.id) {
    manifest.writeAppId(app.id);
    Logger.info('Wrote appId ${app.id} to ${manifest.path}.');
  }
  return app;
}
