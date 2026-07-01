import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

/// A mini-app as the backend knows it: its UUID [id], URL-friendly [slug] (the
/// manifest `id`), and display [name].
class BackendApp {
  const BackendApp({required this.id, required this.slug, required this.name});

  final String id;
  final String slug;
  final String name;
}

/// A super-app of the tenant, as listed by `GET /super-apps`.
class SuperApp {
  const SuperApp({required this.id, required this.name, this.status});

  final String id;
  final String name;
  final String? status;
}

/// An app ↔ super-app binding, as listed by `GET /bindings`.
class AppBindingInfo {
  const AppBindingInfo({
    required this.appId,
    required this.superAppId,
    required this.isActive,
  });

  final String appId;
  final String superAppId;
  final bool isActive;
}

/// The version created by a deploy: its UUID [id], [version] string and
/// lifecycle [status] (e.g. `DRAFT`).
class DeployedVersion {
  const DeployedVersion({this.id, required this.version, this.status});

  final String? id;
  final String version;
  final String? status;
}

/// Raised on any non-success backend response.
class BackendException implements Exception {
  BackendException(this.message, {this.statusCode, this.body});

  final String message;
  final int? statusCode;
  final String? body;

  @override
  String toString() => 'BackendException: $message';
}

/// Thin HTTP client for the Krom backend, authenticated with a Personal Access
/// Token. Covers exactly the developer-facing operations the CLI/extension need:
/// resolve/create an app, upload a version, and bind to a super-app. Review
/// actions (approve/reject/release) are intentionally NOT here — validation is a
/// reviewer's job (OWNER/ADMIN), not a publish-token capability.
class BackendClient {
  BackendClient({
    required String baseUrl,
    required this.token,
    http.Client? httpClient,
  })  : baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _http = httpClient ?? http.Client();

  final String baseUrl;
  final String token;
  final http.Client _http;

  Map<String, String> get _authHeaders => {
        'accept': '*/*',
        'Authorization': 'Bearer $token',
      };

  /// Finds the tenant's app whose slug is [slug] (paging through `GET /apps`),
  /// or null if none matches.
  Future<BackendApp?> findAppBySlug(String slug) async {
    var page = 0;
    while (true) {
      final resp = await _http.get(
        Uri.parse('$baseUrl/api/v1/apps?page=$page&size=100'),
        headers: _authHeaders,
      );
      if (resp.statusCode != 200) {
        throw BackendException('Listing apps failed',
            statusCode: resp.statusCode, body: resp.body);
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final items = (data['items'] as List?) ?? const [];
      for (final raw in items) {
        final m = raw as Map<String, dynamic>;
        if (m['slug'] == slug) return _appFrom(m);
      }
      final totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
      if (++page >= totalPages || items.isEmpty) return null;
    }
  }

  /// The app for [appId], or null when the backend answers 404/403 — unknown
  /// id, or an app of another tenant (the backend hides those as 404).
  Future<BackendApp?> getApp(String appId) async {
    final resp = await _http.get(
      Uri.parse('$baseUrl/api/v1/apps/$appId'),
      headers: _authHeaders,
    );
    if (resp.statusCode == 404 || resp.statusCode == 403) return null;
    if (resp.statusCode != 200) {
      throw BackendException('Fetching app $appId failed',
          statusCode: resp.statusCode, body: resp.body);
    }
    return _appFrom(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// All super-apps of the tenant (paging through `GET /super-apps`).
  Future<List<SuperApp>> listSuperApps() async {
    final out = <SuperApp>[];
    await _forEachPage('$baseUrl/api/v1/super-apps', (m) {
      out.add(SuperApp(
        id: m['id'].toString(),
        name: (m['name'] ?? m['id']).toString(),
        status: m['status']?.toString(),
      ));
    });
    return out;
  }

  /// The bindings of [appId] (paging through `GET /bindings`). The `appId`
  /// query param narrows server-side where supported; the client-side filter
  /// keeps the result correct against backends that ignore it.
  Future<List<AppBindingInfo>> listBindings({required String appId}) async {
    final out = <AppBindingInfo>[];
    await _forEachPage('$baseUrl/api/v1/bindings?appId=$appId', (m) {
      if (m['appId']?.toString() != appId) return;
      out.add(AppBindingInfo(
        appId: appId,
        superAppId: m['superAppId'].toString(),
        isActive: m['isActive'] == true,
      ));
    });
    return out;
  }

  /// Creates an app. Throws [BackendException] on failure (e.g. 409 slug taken).
  Future<BackendApp> createApp({
    required String name,
    required String slug,
    String? description,
  }) async {
    final resp = await _http.post(
      Uri.parse('$baseUrl/api/v1/apps'),
      headers: {..._authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'slug': slug,
        if (description != null && description.isNotEmpty)
          'description': description,
      }),
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw BackendException('Creating app "$slug" failed',
          statusCode: resp.statusCode, body: resp.body);
    }
    return _appFrom(jsonDecode(resp.body) as Map<String, dynamic>);
  }

  /// Returns the app for [slug], creating it if it doesn't exist yet.
  Future<BackendApp> ensureApp({
    required String slug,
    required String name,
    String? description,
  }) async {
    final existing = await findAppBySlug(slug);
    if (existing != null) return existing;
    return createApp(name: name, slug: slug, description: description);
  }

  /// Uploads a signed version package (the `<slug>__<version>.zip`) as a new
  /// DRAFT version of [appId].
  Future<DeployedVersion> deployPackage({
    required String appId,
    required String version,
    required List<int> zipBytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/v1/apps/$appId/versions'),
    )
      ..headers.addAll(_authHeaders)
      ..fields['version'] = version
      ..files.add(http.MultipartFile.fromBytes(
        'package',
        zipBytes,
        filename: filename,
        contentType: MediaType('application', 'zip'),
      ));

    final resp = await http.Response.fromStream(await _http.send(request));
    if (resp.statusCode == 409) {
      throw BackendException('Version $version already exists',
          statusCode: 409, body: resp.body);
    }
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw BackendException('Deploy failed',
          statusCode: resp.statusCode, body: resp.body);
    }
    final m = jsonDecode(resp.body) as Map<String, dynamic>;
    return DeployedVersion(
      id: m['id']?.toString(),
      version: m['versionString']?.toString() ?? version,
      status: m['status']?.toString(),
    );
  }

  /// Submits a DRAFT version for review (DRAFT → IN_REVIEW). This is the
  /// developer's "ready for review" signal — it does NOT approve/release.
  Future<void> submitForReview({
    required String appId,
    required String versionId,
  }) async {
    final resp = await _http.post(
      Uri.parse('$baseUrl/api/v1/apps/$appId/versions/$versionId/submit'),
      headers: _authHeaders,
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw BackendException('Submit-for-review failed',
          statusCode: resp.statusCode, body: resp.body);
    }
  }

  /// Binds [appId] to [superAppId] (idempotent on the backend).
  Future<void> bind({
    required String appId,
    required String superAppId,
  }) async {
    final resp = await _http.post(
      Uri.parse('$baseUrl/api/v1/bindings'),
      headers: {..._authHeaders, 'Content-Type': 'application/json'},
      body: jsonEncode({'appId': appId, 'superAppId': superAppId}),
    );
    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw BackendException('Binding failed',
          statusCode: resp.statusCode, body: resp.body);
    }
  }

  void close() => _http.close();

  /// Visits every item of a paged listing endpoint. [firstPageUrl] may already
  /// carry query params; `page`/`size` are appended.
  Future<void> _forEachPage(
    String firstPageUrl,
    void Function(Map<String, dynamic> item) visit,
  ) async {
    final sep = firstPageUrl.contains('?') ? '&' : '?';
    var page = 0;
    while (true) {
      final resp = await _http.get(
        Uri.parse('$firstPageUrl${sep}page=$page&size=100'),
        headers: _authHeaders,
      );
      if (resp.statusCode != 200) {
        throw BackendException('Listing failed',
            statusCode: resp.statusCode, body: resp.body);
      }
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      final items = (data['items'] as List?) ?? const [];
      for (final raw in items) {
        visit(raw as Map<String, dynamic>);
      }
      final totalPages = (data['totalPages'] as num?)?.toInt() ?? 1;
      if (++page >= totalPages || items.isEmpty) return;
    }
  }

  BackendApp _appFrom(Map<String, dynamic> m) => BackendApp(
        id: m['id'].toString(),
        slug: m['slug'].toString(),
        name: (m['name'] ?? m['slug']).toString(),
      );
}
