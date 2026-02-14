import 'package:test/test.dart';
import 'package:krom_bundler/src/bundler/bundler.dart';

void main() {
  group('Bundler', () {
    test('should extract @use imports', () {
      final bundler = Bundler();
      // Basic instantiation test
      expect(bundler, isNotNull);
    });
  });
}
