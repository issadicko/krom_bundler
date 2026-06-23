import 'package:test/test.dart';
import 'package:krom_bundler/src/utils/config.dart';

void main() {
  group('KromConfig auth token precedence', () {
    // KromConfig is a singleton; reset credential state before each test.
    setUp(() {
      final config = KromConfig();
      config.clearTokens();
    });

    test('authToken prefers accessToken (PAT) over legacy token', () {
      final config = KromConfig();
      config.setToken('legacy-jwt');
      config.setAccessToken('krom_pat_abc');
      expect(config.authToken, 'krom_pat_abc');
      expect(config.isAuthenticated, isTrue);
    });

    test('authToken falls back to legacy token when no PAT', () {
      final config = KromConfig();
      config.setToken('legacy-jwt');
      expect(config.authToken, 'legacy-jwt');
      expect(config.isAuthenticated, isTrue);
    });

    test('empty accessToken falls back to legacy token', () {
      final config = KromConfig();
      config.setToken('legacy-jwt');
      config.setAccessToken('');
      expect(config.authToken, 'legacy-jwt');
    });

    test('isAuthenticated is false with no credentials', () {
      final config = KromConfig();
      expect(config.authToken, isNull);
      expect(config.isAuthenticated, isFalse);
    });

    test('clearTokens removes both credentials', () {
      final config = KromConfig();
      config.setToken('legacy-jwt');
      config.setAccessToken('krom_pat_abc');
      config.clearTokens();
      expect(config.accessToken, isNull);
      expect(config.token, isNull);
      expect(config.isAuthenticated, isFalse);
    });
  });
}
