import 'package:test/test.dart';
import 'package:krom_bundler/src/bundler/manifest_validator.dart';
import 'package:krom_bundler/src/bundler/bundler.dart';

void main() {
  group('ManifestValidator', () {
    Map<String, dynamic> baseManifest() => {
          'id': 'com.example.app',
          'name': 'App',
          'version': '1.0.0',
          'entry': 'home',
          'pages': {
            'home': {'name': 'Home', 'source': 'pages/home.ks'},
            'stats': {'name': 'Stats', 'source': 'pages/stats.ks'},
            'detail': {'name': 'Detail', 'source': 'pages/detail.ks'},
            'export': {'name': 'Export', 'source': 'pages/export.ks'},
          },
        };

    test('accepts a minimal valid manifest', () {
      expect(() => ManifestValidator.validate(baseManifest()), returnsNormally);
    });

    test('accepts a full TCMPP manifest', () {
      final m = baseManifest()
        ..addAll({
          'window': {
            'navigationBarTitleText': 'App',
            'navigationBarBackgroundColor': '#ffffff',
            'navigationBarTextStyle': 'black',
          },
          'tabBar': {
            'list': [
              {'pagePath': 'home', 'text': 'Home', 'iconPath': 'a.png'},
              {'pagePath': 'stats', 'text': 'Stats'},
            ],
          },
          'scopes': {
            'scope.userLocation': {'desc': 'why we need it'},
          },
          'networkTimeout': {
            'request': 10000,
            'uploadFile': 30000,
            'downloadFile': 30000,
          },
          'subpackages': [
            {
              'root': 'pkgA',
              'pages': ['detail', 'export'],
            },
          ],
        });
      expect(() => ManifestValidator.validate(m), returnsNormally);
    });

    group('window', () {
      test('rejects bad navigationBarTextStyle', () {
        final m = baseManifest()
          ..['window'] = {'navigationBarTextStyle': 'blue'};
        expect(
          () => ManifestValidator.validate(m),
          throwsA(isA<BundlerException>().having(
              (e) => e.message, 'message', contains('navigationBarTextStyle'))),
        );
      });

      test('rejects non-hex background color', () {
        final m = baseManifest()
          ..['window'] = {'navigationBarBackgroundColor': 'white'};
        expect(
          () => ManifestValidator.validate(m),
          throwsA(isA<BundlerException>().having((e) => e.message, 'message',
              contains('navigationBarBackgroundColor'))),
        );
      });

      test('rejects unknown window property', () {
        final m = baseManifest()..['window'] = {'unknownKey': 'x'};
        expect(
          () => ManifestValidator.validate(m),
          throwsA(isA<BundlerException>()
              .having((e) => e.message, 'message', contains('unknownKey'))),
        );
      });
    });

    group('tabBar', () {
      test('rejects pagePath not declared in pages', () {
        final m = baseManifest()
          ..['tabBar'] = {
            'list': [
              {'pagePath': 'home', 'text': 'Home'},
              {'pagePath': 'ghost', 'text': 'Ghost'},
            ],
          };
        expect(
          () => ManifestValidator.validate(m),
          throwsA(isA<BundlerException>()
              .having((e) => e.message, 'message', contains('ghost'))),
        );
      });

      test('requires text on each item', () {
        final m = baseManifest()
          ..['tabBar'] = {
            'list': [
              {'pagePath': 'home'},
              {'pagePath': 'stats', 'text': 'Stats'},
            ],
          };
        expect(
          () => ManifestValidator.validate(m),
          throwsA(isA<BundlerException>().having(
              (e) => e.message, 'message', contains('tabBar.list[0].text'))),
        );
      });

      test('rejects a single-item list (needs 2..5)', () {
        final m = baseManifest()
          ..['tabBar'] = {
            'list': [
              {'pagePath': 'home', 'text': 'Home'},
            ],
          };
        expect(
          () => ManifestValidator.validate(m),
          throwsA(isA<BundlerException>().having(
              (e) => e.message, 'message', contains('between 2 and 5'))),
        );
      });
    });

    group('permissions / scopes', () {
      test('requires desc for a scope object', () {
        final m = baseManifest()
          ..['scopes'] = {
            'scope.userLocation': {'reason': 'nope'},
          };
        expect(
          () => ManifestValidator.validate(m),
          throwsA(isA<BundlerException>().having((e) => e.message, 'message',
              contains('scope.userLocation.desc'))),
        );
      });

      test('accepts legacy list of scope names', () {
        final m = baseManifest()..['permissions'] = ['scope.camera'];
        expect(() => ManifestValidator.validate(m), returnsNormally);
      });
    });

    group('networkTimeout', () {
      test('rejects non-positive values', () {
        final m = baseManifest()..['networkTimeout'] = {'request': 0};
        expect(
          () => ManifestValidator.validate(m),
          throwsA(isA<BundlerException>().having((e) => e.message, 'message',
              contains('networkTimeout.request'))),
        );
      });

      test('rejects unknown timeout key', () {
        final m = baseManifest()..['networkTimeout'] = {'foo': 1000};
        expect(
          () => ManifestValidator.validate(m),
          throwsA(isA<BundlerException>()
              .having((e) => e.message, 'message', contains('foo'))),
        );
      });
    });

    group('subpackages', () {
      test('requires root and pages', () {
        final m = baseManifest()
          ..['subpackages'] = [
            {'pages': <String>[]},
          ];
        expect(
          () => ManifestValidator.validate(m),
          throwsA(isA<BundlerException>()),
        );
      });

      test('rejects duplicate roots', () {
        final m = baseManifest()
          ..['subpackages'] = [
            {
              'root': 'pkg',
              'pages': ['detail'],
            },
            {
              'root': 'pkg',
              'pages': ['export'],
            },
          ];
        expect(
          () => ManifestValidator.validate(m),
          throwsA(isA<BundlerException>()
              .having((e) => e.message, 'message', contains('duplicates'))),
        );
      });

      test('accepts subPackages camelCase alias', () {
        final m = baseManifest()
          ..['subPackages'] = [
            {
              'root': 'pkg',
              'pages': ['detail'],
            },
          ];
        expect(() => ManifestValidator.validate(m), returnsNormally);
      });

      test('rejects a page not declared in pages', () {
        final m = baseManifest()
          ..['subpackages'] = [
            {
              'root': 'pkg',
              'pages': ['ghostPage'],
            },
          ];
        expect(
          () => ManifestValidator.validate(m),
          throwsA(isA<BundlerException>().having((e) => e.message, 'message',
              contains('ghostPage'))),
        );
      });

      test('rejects a page assigned to two subpackages', () {
        final m = baseManifest()
          ..['subpackages'] = [
            {
              'root': 'pkgA',
              'pages': ['detail'],
            },
            {
              'root': 'pkgB',
              'pages': ['detail'],
            },
          ];
        expect(
          () => ManifestValidator.validate(m),
          throwsA(isA<BundlerException>().having((e) => e.message, 'message',
              contains('only one subpackage'))),
        );
      });
    });

    test('aggregates multiple errors in one exception', () {
      final m = baseManifest()
        ..['window'] = {'navigationBarTextStyle': 'blue'}
        ..['networkTimeout'] = {'request': -1};
      expect(
        () => ManifestValidator.validate(m),
        throwsA(isA<BundlerException>()
            .having((e) => e.message, 'message', contains('2 errors'))),
      );
    });
  });
}
