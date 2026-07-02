import 'package:krom_bundler/src/utils/terminal_qr.dart';
import 'package:test/test.dart';

void main() {
  group('terminalQr', () {
    test('renders a half-block ANSI grid with a quiet zone', () {
      final out = terminalQr('http://192.168.1.34:3000');
      expect(out, isNotEmpty);
      final lines = out.trimRight().split('\n');
      // Half-block rendering halves the height; a v2+ QR with quiet zone is
      // at least (25 + 4) / 2 rows tall.
      expect(lines.length, greaterThanOrEqualTo(14));
      // Every line resets its ANSI styling (no color bleed into the shell).
      for (final line in lines) {
        expect(line, endsWith('\x1B[0m'));
        expect(line, contains('▀'));
      }
      // Deterministic for a fixed payload.
      expect(terminalQr('http://192.168.1.34:3000'), out);
    });

    test('returns empty for an un-encodable payload', () {
      expect(terminalQr('x' * 8000), isEmpty);
    });
  });
}
