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
            'backgroundColor': '#0b0c0e',
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

    group('id', () {
      test('accepts a slug, an init-style name and a reverse-DNS id', () {
        for (final id in ['wallet', 'my_app-2', 'com.example.app', '2048']) {
          expect(
            () => ManifestValidator.validate(baseManifest()..['id'] = id),
            returnsNormally,
            reason: id,
          );
        }
      });

      test('rejects an id that would leave the package cache', () {
        // The slug becomes a folder of the package cache on the device.
        const unsafe = ['..', '.', 'a/b', r'a\b', 'c:', 'a b', '', '.hidden'];
        for (final id in unsafe) {
          expect(
            () => ManifestValidator.validate(baseManifest()..['id'] = id),
            throwsA(isA<BundlerException>()
                .having((e) => e.message, 'message', contains('"id"'))),
            reason: id,
          );
        }
      });

      test('rejects a non-string id', () {
        expect(
          () => ManifestValidator.validate(baseManifest()..['id'] = 42),
          throwsA(isA<BundlerException>()),
        );
      });
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

      test('rejects a background color that is not opaque #RRGGBB', () {
        for (final color in ['white', '#fff', '#800b0c0e', 12]) {
          final m = baseManifest()..['window'] = {'backgroundColor': color};
          expect(
            () => ManifestValidator.validate(m),
            throwsA(isA<BundlerException>().having((e) => e.message,
                'message', contains('window.backgroundColor'))),
            reason: '$color',
          );
        }
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
          throwsA(isA<BundlerException>().having(
              (e) => e.message, 'message', contains('networkTimeout.request'))),
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
          throwsA(isA<BundlerException>()
              .having((e) => e.message, 'message', contains('ghostPage'))),
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
          throwsA(isA<BundlerException>().having(
              (e) => e.message, 'message', contains('only one subpackage'))),
        );
      });
    });

    group('workers', () {
      Matcher fails(String message) => throwsA(isA<BundlerException>()
          .having((e) => e.message, 'message', contains(message)));

      test('accepts a name mapped to { source: <file>.ks }', () {
        final m = baseManifest()
          ..['workers'] = {
            'transactions': {'source': 'workers/transactions.ks'},
            '_stats2': {'source': 'stats.ks'},
          };
        expect(() => ManifestValidator.validate(m), returnsNormally);
      });

      test('rejects anything but an object', () {
        final m = baseManifest()..['workers'] = ['workers/a.ks'];
        expect(() => ManifestValidator.validate(m),
            fails('"workers" must be an object'));
      });

      test('rejects a name that is not an identifier', () {
        for (final name in const ['my-worker', '1stats', 'a.b', '']) {
          final m = baseManifest()
            ..['workers'] = {
              name: {'source': 'workers/a.ks'}
            };
          expect(() => ManifestValidator.validate(m),
              fails('"workers.$name" is not a valid worker name'),
              reason: name);
        }
      });

      test('rejects the bare-path form', () {
        final m = baseManifest()..['workers'] = {'stats': 'workers/stats.ks'};
        expect(() => ManifestValidator.validate(m),
            fails('"workers.stats" must be an object'));
      });

      test('requires a .ks source and nothing else', () {
        final missing = baseManifest()
          ..['workers'] = {'stats': <String, dynamic>{}};
        expect(() => ManifestValidator.validate(missing),
            fails('"workers.stats.source" is required.'));

        for (final source in const [42, 'workers/stats.js']) {
          final m = baseManifest()
            ..['workers'] = {
              'stats': {'source': source}
            };
          expect(() => ManifestValidator.validate(m),
              fails('"workers.stats.source" must be the path of a .ks file'),
              reason: '$source');
        }

        final extra = baseManifest()
          ..['workers'] = {
            'stats': {'source': 'workers/stats.ks', 'name': 'Stats'}
          };
        expect(() => ManifestValidator.validate(extra),
            fails('"workers.stats.name" is not a recognised property'));
      });

      test('"worker" is a host namespace, not a dependency name', () {
        final m = baseManifest()
          ..['dependencies'] = {
            'worker': {'git': 'https://git.example/w.git', 'ref': 'v1'}
          };
        expect(() => ManifestValidator.validate(m),
            fails('collides with the "worker" host namespace'));
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
