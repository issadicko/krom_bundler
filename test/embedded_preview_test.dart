import 'dart:convert';

import 'package:krom_bundler/src/preview/embedded_preview.dart';
import 'package:test/test.dart';

void main() {
  group('EmbeddedPreview', () {
    test('a preview is embedded in the CLI', () {
      expect(EmbeddedPreview.isAvailable, isTrue,
          reason: 'run `make embed-preview` to regenerate the embedded preview');
      expect(EmbeddedPreview.buildId, isNotEmpty);
    });

    test('index.html decodes to the Flutter bootstrap page', () {
      final bytes = EmbeddedPreview.read('index.html');
      expect(bytes, isNotNull);
      final html = utf8.decode(bytes!);
      expect(html.toLowerCase(), contains('<!doctype html'));
      // The Flutter loader script is what boots the preview app.
      expect(html, contains('flutter.js'));
    });

    test('the empty path and a leading slash both resolve to index.html', () {
      final root = EmbeddedPreview.read('');
      final slashIndex = EmbeddedPreview.read('/index.html');
      final index = EmbeddedPreview.read('index.html');
      expect(root, isNotNull);
      expect(root, same(index)); // decoded once, then cached
      expect(slashIndex, same(index));
    });

    test('main.dart.js is embedded and non-trivial', () {
      final bytes = EmbeddedPreview.read('main.dart.js');
      expect(bytes, isNotNull);
      expect(bytes!.length, greaterThan(100000)); // ~3 MB in practice
    });

    test('CanvasKit is NOT embedded (served from the gstatic CDN)', () {
      expect(EmbeddedPreview.read('canvaskit/canvaskit.wasm'), isNull);
      expect(EmbeddedPreview.read('canvaskit/canvaskit.js'), isNull);
    });

    test('an unknown asset returns null', () {
      expect(EmbeddedPreview.read('nope/missing.js'), isNull);
    });
  });
}
