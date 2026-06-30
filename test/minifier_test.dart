import 'package:krom_bundler/src/bundler/minifier.dart';
import 'package:test/test.dart';

void main() {
  group('minifyKromSource', () {
    test('preserves URLs — // inside a string is not a comment', () {
      final out = minifyKromSource('let BASE = "https://dummyjson.com"');
      expect(out, 'let BASE="https://dummyjson.com"');
      expect(out, contains('https://dummyjson.com'));
    });

    test('removes spaces around operators/punctuation (not a literal \$1)', () {
      final out = minifyKromSource('fn add(a, b) { return a + b }');
      expect(out, 'fn add(a,b){return a+b}');
      expect(out, isNot(contains(r'$1')));
    });

    test('strips line comments outside strings', () {
      final out = minifyKromSource('let x = 1 // a comment\nlet y = 2');
      expect(out, 'let x=1 let y=2');
      expect(out, isNot(contains('comment')));
    });

    test('never minifies the content of a string literal', () {
      final out = minifyKromSource('let s = "a + b , c : d"');
      expect(out, 'let s="a + b , c : d"');
    });

    test('honours escaped quotes inside strings', () {
      final out = minifyKromSource(r'let s = "a \" b // c"');
      expect(out, contains(r'"a \" b // c"'));
    });

    test('preserves template literals verbatim', () {
      final out = minifyKromSource(r'let s = `x://y ${ a + b }`');
      expect(out, contains(r'`x://y ${ a + b }`'));
    });

    test('collapses whitespace and newlines', () {
      final out = minifyKromSource('let   x   =   1\n\n\nlet y = 2');
      expect(out, 'let x=1 let y=2');
    });
  });
}
