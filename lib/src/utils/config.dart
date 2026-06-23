import 'dart:convert';
import 'dart:io';
import 'package:path/path.dart' as p;

/// Persistent CLI configuration stored at `~/.krom/config.json`.
///
/// Schema:
/// ```json
/// {
///   "remoteUrl": "https://api.example.com",
///   "token": "<legacy JWT>",
///   "accessToken": "krom_pat_..."
/// }
/// ```
///
/// [token] is kept for backward compatibility with the legacy
/// email/password login flow. [accessToken] holds a Personal Access
/// Token (PAT). Authenticated requests should use [authToken], which
/// prefers the PAT and falls back to the legacy JWT.
class KromConfig {
  static final KromConfig _instance = KromConfig._internal();
  factory KromConfig() => _instance;
  KromConfig._internal();

  String? _remoteUrl;
  String? _token;
  String? _accessToken;

  String? get remoteUrl => _remoteUrl;

  /// Legacy JWT obtained via email/password login. Kept for retro-compat.
  String? get token => _token;

  /// Personal Access Token (PAT), e.g. `krom_pat_...`.
  String? get accessToken => _accessToken;

  /// The token to use for authenticated requests.
  ///
  /// Prefers the Personal Access Token, falling back to the legacy JWT.
  String? get authToken =>
      (_accessToken != null && _accessToken!.isNotEmpty) ? _accessToken : _token;

  /// Whether any credential is currently stored.
  bool get isAuthenticated {
    final t = authToken;
    return t != null && t.isNotEmpty;
  }

  File get _configFile {
    final home = Platform.isWindows
        ? Platform.environment['APPDATA']
        : Platform.environment['HOME'];
    final configDir = p.join(home!, '.krom');
    return File(p.join(configDir, 'config.json'));
  }

  Future<void> load() async {
    final file = _configFile;
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        _remoteUrl = data['remoteUrl'] as String?;
        _token = data['token'] as String?;
        _accessToken = data['accessToken'] as String?;
      } catch (_) {
        // Ignore errors, use defaults
      }
    }
  }

  Future<void> save() async {
    final file = _configFile;
    if (!await file.parent.exists()) {
      await file.parent.create(recursive: true);
    }
    final data = <String, dynamic>{
      if (_remoteUrl != null) 'remoteUrl': _remoteUrl,
      if (_token != null) 'token': _token,
      if (_accessToken != null) 'accessToken': _accessToken,
    };
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
  }

  void setRemoteUrl(String url) {
    _remoteUrl = url;
  }

  /// Store the legacy JWT (email/password flow).
  void setToken(String? token) {
    _token = token;
  }

  /// Store a Personal Access Token (PAT).
  void setAccessToken(String? accessToken) {
    _accessToken = accessToken;
  }

  /// Clear all stored credentials (both PAT and legacy JWT).
  void clearTokens() {
    _token = null;
    _accessToken = null;
  }
}
