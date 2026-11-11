import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:archive/archive.dart';
import 'package:krom_bundler/src/bundler/asset_packager.dart';
import 'package:krom_bundler/src/bundler/bundler.dart';
import 'package:krom_bundler/src/bundler/manifest_bundler.dart';
import 'package:krom_bundler/src/server/dev_server.dart';
import 'package:krom_script/krom_script.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Un projet jetable. [files] est un chemin relatif -> contenu.
Directory _project(Map<String, String> files) {
  final dir = Directory.systemTemp.createTempSync('krom_workers_');
  files.forEach((relative, content) {
    final file = File(p.join(dir.path, relative));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  });
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

String _manifest({
  Map<String, String> workers = const {'stats': 'workers/stats.ks'},
  Map<String, String> pages = const {'home': 'pages/home.ks'},
  Map<String, String> components = const {},
  Map<String, Object?> extra = const {},
}) =>
    jsonEncode({
      'id': 'w',
      'name': 'W',
      'version': '1.0.0',
      'entry': pages.keys.first,
      'pages': {
        for (final e in pages.entries) e.key: {'name': e.key, 'source': e.value}
      },
      if (components.isNotEmpty)
        'components': {
          for (final e in components.entries)
            e.key: {'name': e.key, 'source': e.value}
        },
      if (workers.isNotEmpty)
        'workers': {
          for (final e in workers.entries) e.key: {'source': e.value}
        },
      ...extra,
    });

const _home = 'fn build() { return Text("") }\n';

const _stats = 'fn summarize(rows) {\n'
    '  let total = 0\n'
    '  for (r in rows) { total = total + r }\n'
    '  return { total: total, count: size(rows) }\n'
    '}\n';

/// Un projet minimal : la page [home] et le worker `stats` [stats].
Directory _app({
  String home = _home,
  String stats = _stats,
  Map<String, String> more = const {},
  String? manifest,
}) =>
    _project({
      'manifest.json': manifest ?? _manifest(),
      'pages/home.ks': home,
      'workers/stats.ks': stats,
      ...more,
    });

Future<Map<String, dynamic>> _build(Directory dir,
        {bool optimize = false, bool minify = false, bool sourceMap = false}) =>
    ManifestBundler(
      enableOptimizer: optimize,
      minify: minify,
      emitSourceMap: sourceMap,
    ).bundleProjectToMap(p.join(dir.path, 'manifest.json'));

Future<String> _error(Directory dir) async {
  try {
    await _build(dir);
  } on BundlerException catch (e) {
    return e.message;
  }
  fail('le build aurait dû échouer');
}

String _script(Map<String, dynamic> out, String worker) =>
    ((out['workers'] as Map)[worker] as Map)['script'] as String;

/// Le `worker` d'un isolate : `progress`, rien d'autre.
class _Progress implements KromBindable {
  final List<Object?> values = [];

  @override
  Object? getProperty(String name) => null;

  @override
  Object? callMethod(String name, List<Object?> args) {
    if (name == 'progress') values.add(args.isEmpty ? null : args.first);
    return null;
  }
}

/// Charge [script] comme le runtime charge un worker — un moteur nu, plus
/// `worker.progress` — et appelle [function].
Future<Object?> _runWorker(String script, String function,
    [List<Object?> args = const []]) async {
  final engine = KSEngine()..bind('worker', _Progress());
  final loaded = await engine.load(script, enableOptimizer: false);
  expect(loaded.success, isTrue, reason: loaded.errors.join('\n'));
  final result = engine.invokeSynchronized(function, args);
  expect(result.success, isTrue, reason: result.errors.join('\n'));
  return result.value;
}

const _r1 = "n'existe pas dans un worker : seuls le langage et "
    'worker.progress y sont disponibles.';
const _r2 = "Un worker ne peut pas lancer d'autre worker : seul "
    'worker.progress existe ici.';

void main() {
  group('bundling', () {
    test('le worker sort sous "workers", avec ce qu\'il importe', () async {
      final dir = _app(
        stats: '@use "../utils/math.ks"\n'
            'fn summarize(rows) { return clamp(size(rows), 0, 2) }\n',
        more: {
          'utils/math.ks': 'fn clamp(v, lo, hi) {\n'
              '  if (v < lo) { return lo }\n'
              '  if (v > hi) { return hi }\n'
              '  return v\n'
              '}\n',
        },
      );

      final out = await _build(dir);
      final worker = (out['workers'] as Map)['stats'] as Map;
      expect(worker.keys, ['script']);
      expect(worker['script'], contains('fn clamp('));
      expect(
          await _runWorker(_script(out, 'stats'), 'summarize', [
            [1, 2, 3]
          ]),
          2);
      expect((out['pages'] as Map).keys, ['home']);
    });

    test('sans workers déclarés, la sortie n\'a pas de clé "workers"',
        () async {
      final dir = _app(manifest: _manifest(workers: const {}));
      expect((await _build(dir)).containsKey('workers'), isFalse);
    });

    test('en développement, le worker porte sa source map', () async {
      final dir = _app(
        stats: '@use "../utils/math.ks"\n$_stats',
        more: {'utils/math.ks': 'fn twice(n) { return n * 2 }\n'},
      );

      final out = await _build(dir, sourceMap: true);
      final map = ((out['workers'] as Map)['stats'] as Map)['sourceMap'];
      expect([for (final s in map as List) s['f']],
          ['utils/math.ks', 'workers/stats.ks']);
    });

    test('optimisé et minifié, le worker garde ses fonctions', () async {
      // Rien dans le bundle d'un worker n'appelle ses fonctions : l'élagage
      // des pages les retirerait toutes.
      final dir = _app(
        stats: 'let SCALE = 10\n'
            'fn scaled(n) { return n * SCALE }\n'
            'let half = fn(n) { return n / 2 }\n'
            'fn report(rows) {\n'
            '  worker.progress(0.5)\n'
            '  return { total: scaled(size(rows)) }\n'
            '}\n',
      );

      final out = await _build(dir, optimize: true, minify: true);
      final script = _script(out, 'stats');
      expect(
          await _runWorker(script, 'report', [
            [1, 2]
          ]),
          {'total': 20});
      expect(await _runWorker(script, 'half', [8]), 4);
    });

    test('une dépendance scellée se bundle dans un worker', () async {
      const git = 'https://git.example/ks-money.git';
      final dir = _app(
        manifest: _manifest(extra: {
          'dependencies': {
            'money': {'git': git, 'ref': 'v1.0.0'}
          },
        }),
        stats: '@use "money/format" as fmt\n'
            'fn label(n) { return fmt.label(n) }\n',
        more: {
          'krom.lock': jsonEncode({
            'version': 1,
            'deps': {
              'money': {'git': git, 'ref': 'v1.0.0', 'commit': 'abc123'}
            },
          }),
          '.krom/deps/money/.dep.json':
              jsonEncode({'git': git, 'ref': 'v1.0.0', 'commit': 'abc123'}),
          '.krom/deps/money/format.ks':
              'fn label(n) { return "" + n + " F" }\n',
        },
      );

      final out = await _build(dir);
      expect(await _runWorker(_script(out, 'stats'), 'label', [5]), '5 F');
    });

    test('un fichier de worker absent fait échouer le build', () async {
      final dir = _app(manifest: _manifest(workers: {'stats': 'workers/x.ks'}));
      expect(await _error(dir), contains('File not found'));
    });

    test('le paquet de deploy/publish embarque les workers', () async {
      final dir = _app();
      final compiled = await _build(dir);
      final pkg = await AssetPackager.build(
        compiledManifest: compiled,
        projectDir: dir.path,
      );
      final archive = ZipDecoder().decodeBytes(pkg.zipBytes);
      final appJson = jsonDecode(
              utf8.decode(archive.findFile('app.json')!.content as List<int>))
          as Map<String, dynamic>;
      expect((appJson['workers'] as Map)['stats']['script'],
          contains('fn summarize('));
    });

    test('les stats comptent un module partagé entre page et worker', () async {
      final dir = _app(
        home: '@use "../utils/math.ks"\n$_home',
        stats: '@use "../utils/math.ks"\n$_stats',
        more: {'utils/math.ks': 'fn twice(n) { return n * 2 }\n'},
      );
      final bundler = ManifestBundler();
      await bundler.bundleProjectToMap(p.join(dir.path, 'manifest.json'));
      final shared = bundler.stats.duplicated.single;
      expect(p.basename(shared.path), 'math.ks');
      expect(shared.copies, 2);
    });

    test('worker est un namespace de l\'hôte : pas un alias', () async {
      final dir = _app(
        home: '@use "../utils/math.ks" as worker\n$_home',
        more: {'utils/math.ks': 'fn twice(n) { return n * 2 }\n'},
      );
      expect(await _error(dir), contains('Alias "worker"'));
    });
  });

  group('R1 : rien de la page dans un worker', () {
    for (final name in const [
      'storage',
      'request',
      'nav',
      'ui',
      'timer',
      'device',
      'args',
      'clipboard',
      'theme',
    ]) {
      test('« $name » est refusé', () async {
        final dir = _app(stats: 'fn f() {\n  return $name\n}\n');
        expect(await _error(dir), 'workers/stats.ks:2:10: « $name » $_r1');
      });
    }

    test('les composants et modules de lib, même déclarés', () async {
      final dir = _app(
        manifest: _manifest(extra: {
          'requires': ['charts']
        }),
        stats: 'fn f(rows) {\n'
            '  let s = LineChart({})\n'
            '  return charts.niceScale(0, 10)\n'
            '}\n',
      );
      final error = await _error(dir);
      expect(error, contains('workers/stats.ks:2:11: « LineChart » $_r1'));
      expect(error, contains('workers/stats.ks:3:10: « charts » $_r1'));
    });

    test('les customWidgets du manifeste', () async {
      final dir = _app(
        manifest: _manifest(extra: {
          'customWidgets': ['RatingStars']
        }),
        stats: 'fn f() { return RatingStars({}) }\n',
      );
      expect(await _error(dir), contains('« RatingStars » $_r1'));
    });

    test('un fichier importé est situé chez lui', () async {
      final dir = _app(
        stats: '@use "../utils/cache.ks"\n$_stats',
        more: {
          'utils/cache.ks': 'fn save(v) {\n'
              '  storage.setItem("v", v)\n'
              '}\n',
        },
      );
      expect(await _error(dir), 'utils/cache.ks:2:3: « storage » $_r1');
    });

    test('une dépendance aussi', () async {
      const git = 'https://git.example/ks-money.git';
      final dir = _app(
        manifest: _manifest(extra: {
          'dependencies': {
            'money': {'git': git, 'ref': 'v1.0.0'}
          },
        }),
        stats: '@use "money" as money\n$_stats',
        more: {
          'krom.lock': jsonEncode({
            'version': 1,
            'deps': {
              'money': {'git': git, 'ref': 'v1.0.0', 'commit': 'abc123'}
            },
          }),
          '.krom/deps/money/.dep.json':
              jsonEncode({'git': git, 'ref': 'v1.0.0', 'commit': 'abc123'}),
          '.krom/deps/money/main.ks': 'fn rate() { return request({}) }\n',
        },
      );
      expect(
          await _error(dir), '.krom/deps/money/main.ks:1:20: « request » $_r1');
    });

    test('un nom que le fichier lie lui-même n\'est pas signalé', () async {
      final dir = _app(
        stats: 'let storage = []\n'
            'fn keep(v) { storage = storage + [v] }\n'
            'fn f(ui, timer) { return ui + timer }\n'
            'fn g(rows) {\n'
            '  for (nav in rows) { print(nav) }\n'
            '  if (size(rows) > 0) { let device = rows[0] }\n'
            '  return device\n'
            '}\n'
            'fn h() {\n'
            '  args = 1\n'
            '  let o = { theme: 1, clipboard: "x" }\n'
            '  return o.theme + args + "request"\n'
            '}\n'
            'let pick = fn(request) { return request }\n'
            'fn worker() { return 1 }\n',
      );
      await _build(dir);
    });

    test('un nom posé par un module importé à plat est le sien', () async {
      final dir = _app(
        stats: '@use "../utils/fake.ks"\n'
            'fn f() { return timer.now() }\n',
        more: {'utils/fake.ks': 'let timer = { now: fn() { return 1 } }\n'},
      );
      await _build(dir);
    });
  });

  group('R2 : pas de worker dans un worker', () {
    test('worker.run et worker.cancel sont refusés', () async {
      final dir = _app(
        stats: 'fn f() {\n'
            '  let id = worker.run("stats.f", [])\n'
            '  return worker.cancel(id)\n'
            '}\n',
      );
      expect(
          await _error(dir),
          'workers/stats.ks:2:12: $_r2\n'
          '  workers/stats.ks:3:10: $_r2');
    });

    test('worker.progress est permis', () async {
      final dir = _app(stats: 'fn f(n) { worker.progress(n / 2) }\n');
      await _build(dir);
    });

    test('un worker qui définit son propre « worker » n\'est pas signalé',
        () async {
      final dir = _app(
        stats: 'let worker = { run: fn(a, b) { return a } }\n'
            'fn f() { return worker.run("x", []) }\n',
      );
      await _build(dir);
    });
  });

  group('R3 : la cible de worker.run', () {
    Future<String?> pageError(String body,
        {String stats = _stats, Map<String, String> more = const {}}) async {
      final dir = _app(
        home: 'fn start(x) {\n  $body\n}\n$_home',
        stats: stats,
        more: more,
      );
      try {
        await _build(dir);
        return null;
      } on BundlerException catch (e) {
        return e.message;
      }
    }

    test('une cible valide passe', () async {
      expect(
          await pageError(
              'worker.run("stats.summarize", [[1]], "onDone", "onError")'),
          isNull);
    });

    test('un worker inconnu', () async {
      expect(
          await pageError('worker.run("ghost.summarize", [])'),
          'pages/home.ks:2:14: Worker « ghost » inconnu : déclarez-le dans '
          'manifest.json, sous "workers".');
    });

    test('une fonction absente', () async {
      expect(await pageError('worker.run("stats.nope", [])'),
          'pages/home.ks:2:14: Le worker « stats » n\'a pas de fonction « nope ».');
    });

    test('un nom qui n\'est pas une fonction', () async {
      expect(
          await pageError('worker.run("stats.LIMIT", [])',
              stats: 'let LIMIT = 10\n$_stats'),
          contains('n\'a pas de fonction « LIMIT »'));
    });

    test('un littéral sans point, ou qui commence par un point', () async {
      for (final target in const ['stats', '.summarize']) {
        expect(await pageError('worker.run("$target", [])'),
            'pages/home.ks:2:14: worker.run attend "worker.fonction".');
      }
    });

    test('une cible non littérale n\'est pas vérifiée', () async {
      expect(await pageError('worker.run(x, [])'), isNull);
      expect(await pageError('worker.run("ghost." + x, [])'), isNull);
    });

    test('une fonction importée à plat, ou posée par let, est visible',
        () async {
      expect(
          await pageError('worker.run("stats.twice", [1])',
              stats: '@use "../utils/math.ks"\n$_stats',
              more: {'utils/math.ks': 'fn twice(n) { return n * 2 }\n'}),
          isNull);
      expect(
          await pageError('worker.run("stats.half", [1])',
              stats: 'let half = fn(n) { return n / 2 }\n'),
          isNull);
    });

    test('une cible pointée passe par un namespace du worker', () async {
      final more = {'utils/math.ks': 'fn twice(n) { return n * 2 }\n'};
      final stats = '@use "../utils/math.ks" as math\n$_stats';
      expect(
          await pageError('worker.run("stats.math.twice", [1])',
              stats: stats, more: more),
          isNull);
      expect(
          await pageError('worker.run("stats.maths.twice", [1])',
              stats: stats, more: more),
          contains('n\'a pas de fonction « maths.twice »'));
    });

    test('un composant est vérifié comme une page', () async {
      final dir = _project({
        'manifest.json': _manifest(components: {'card': 'components/card.ks'}),
        'pages/home.ks': _home,
        'workers/stats.ks': _stats,
        'components/card.ks': 'fn go() { worker.run("stats.nope", []) }\n',
      });
      expect(await _error(dir), startsWith('components/card.ks:1:22: '));
    });

    test('une page qui lie « worker » elle-même n\'est pas vérifiée', () async {
      expect(
          await pageError('let worker = { run: fn(a) { return a } }\n'
              '  worker.run("ghost.f")'),
          isNull);
      final dir = _app(
        home: 'fn start(worker) { return worker.run("ghost.f") }\n$_home',
      );
      await _build(dir);
    });
  });

  group('R4 : worker.progress hors d\'un worker', () {
    test('refusé dans une page', () async {
      final dir = _app(home: 'fn tick() {\n  worker.progress(1)\n}\n$_home');
      expect(await _error(dir),
          'pages/home.ks:2:3: worker.progress n\'existe que dans un worker.');
    });

    test('refusé dans un composant', () async {
      final dir = _project({
        'manifest.json': _manifest(components: {'card': 'components/card.ks'}),
        'pages/home.ks': _home,
        'workers/stats.ks': _stats,
        'components/card.ks': 'fn go() { worker.progress(1) }\n',
      });
      expect(await _error(dir),
          'components/card.ks:1:11: worker.progress n\'existe que dans un worker.');
    });

    test('pas de faux positif sur un « worker » local', () async {
      final dir = _app(
        home: 'fn tick(worker) { worker.progress(1) }\n$_home',
      );
      await _build(dir);
    });
  });

  group('krom dev', () {
    test('modifier un fichier importé par un worker reconstruit le bundle',
        () async {
      final dir = _app(
        stats: '@use "../utils/math.ks"\n$_stats',
        more: {'utils/math.ks': 'fn twice(n) { return n * 2 }\n'},
      );
      final port = 39000 + Random().nextInt(999);
      final server = DevServer(
        manifestBundler: ManifestBundler(emitSourceMap: true),
        manifestPath: p.join(dir.path, 'manifest.json'),
        host: '127.0.0.1',
        port: port,
      );
      await runZoned(
        server.start,
        zoneSpecification: ZoneSpecification(print: (_, __, ___, ____) {}),
      );
      addTearDown(server.stop);

      final ws = await WebSocket.connect('ws://127.0.0.1:$port/ws');
      final frames = ws.asBroadcastStream();
      final first = jsonDecode(
          await frames.first.timeout(const Duration(seconds: 5)) as String);
      expect(_script(first, 'stats'), contains('n * 2'));

      // Le watcher démarre de façon asynchrone : on lui laisse le temps.
      await Future<void>.delayed(const Duration(seconds: 1));
      File(p.join(dir.path, 'utils', 'math.ks'))
          .writeAsStringSync('fn twice(n) { return n * 3 }\n');

      final next = await frames
          .map((f) => jsonDecode(f as String) as Map<String, dynamic>)
          .firstWhere((m) => _script(m, 'stats').contains('n * 3'))
          .timeout(const Duration(seconds: 10));
      expect(_script(next, 'stats'), contains('n * 3'));
      await ws.close();
    });
  });
}
