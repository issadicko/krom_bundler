import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:args/command_runner.dart';
import 'package:path/path.dart' as p;

import '../backend/backend_client.dart';
import '../backend/project_ref.dart';
import '../bundler/asset_packager.dart';
import '../bundler/bundler.dart';
import '../bundler/manifest_bundler.dart';
import '../utils/config.dart';
import '../utils/logger.dart';
import '../utils/project_cache.dart';

/// `krom publish` — one-shot developer publish with a Personal Access Token:
/// build the version package, create the app on the backend if it doesn't exist
/// yet, upload the version, and (optionally) bind it to a super-app.
///
/// It deliberately stops before validation: a version lands as DRAFT (or, with
/// `--submit`, IN_REVIEW). Approving/releasing stays a reviewer action
/// (OWNER/ADMIN) — the PAT flow can publish and bind, never validate.
class PublishCommand extends Command<int> {
  @override
  final name = 'publish';

  @override
  final description =
      'Build, create-if-missing, and deploy this mini-app to the backend (PAT).';

  PublishCommand() {
    argParser
      ..addOption('manifest',
          abbr: 'm', help: 'Path to manifest.json', defaultsTo: 'manifest.json')
      ..addMultiOption('bind',
          help: 'Super-app id(s) (UUID) to bind this app to after publishing. '
              'Repeatable — a mini-app can be bound to several super-apps.')
      ..addFlag('submit',
          help: 'Submit the new version for review (DRAFT -> IN_REVIEW).',
          defaultsTo: false)
      ..addFlag('build',
          help: 'Build a fresh package before publishing.', defaultsTo: true)
      ..addFlag('bump',
          help: 'When the version already exists on the backend (409), bump '
              'the patch version in manifest.json, rebuild and retry once.',
          defaultsTo: false)
      ..addFlag('minify', help: 'Minify the build.', defaultsTo: false);
  }

  @override
  Future<int> run() async {
    final config = KromConfig();
    final remoteUrl = config.remoteUrl;
    final token = config.authToken;

    if (remoteUrl == null || remoteUrl.isEmpty) {
      Logger.error('Remote URL not set.');
      Logger.hint('Use "krom --set-remote=URL" to set the backend URL.');
      return 1;
    }
    if (token == null || token.isEmpty) {
      Logger.error('Not authenticated.');
      Logger.hint('Run "krom login --with-token" with a Personal Access Token.');
      return 1;
    }

    final manifestPath = argResults!['manifest'] as String;
    final superAppIds = (argResults!['bind'] as List<String>)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final submit = argResults!['submit'] as bool;
    final build = argResults!['build'] as bool;
    final bump = argResults!['bump'] as bool;
    final minify = argResults!['minify'] as bool;

    if (!File(manifestPath).existsSync()) {
      Logger.error('Manifest not found: $manifestPath');
      Logger.hint('Run "krom init <name>" to scaffold a project.');
      return 1;
    }

    final ManifestRef manifest;
    try {
      manifest = ManifestRef.load(manifestPath);
    } catch (e) {
      Logger.error('Invalid manifest.json: $e');
      return 1;
    }
    if (manifest.slug == null) {
      Logger.error('manifest.json must have an "id" (used as the app slug).');
      return 1;
    }
    final slug = manifest.slug!;

    final client = BackendClient(baseUrl: remoteUrl, token: token);
    try {
      final steps = superAppIds.isNotEmpty ? 3 : 2;

      // 1. Build the signed-ready package (unless reusing an existing one).
      final _Package pkg = build
          ? await _buildPackage(manifestPath, minify: minify)
          : _newestPackage(manifestPath);
      Logger.keyValue('Version', pkg.version);
      Logger.keyValue('Package', p.basename(pkg.path));

      // 2. Resolve the app: the manifest appId when valid, else by slug
      //    (create-if-missing) — writing the UUID back into the manifest.
      Logger.step(1, steps, 'Resolving app "$slug"...');
      final app = (await resolveProjectApp(client: client, manifest: manifest))!;
      Logger.keyValue('App', '${app.name} (${app.id})');

      // 3. Upload the version (lands as DRAFT). On a 409 with --bump, the
      //    patch version is bumped in the manifest, rebuilt and retried once.
      var package = pkg;
      DeployedVersion deployed;
      try {
        Logger.step(2, steps, 'Deploying version ${package.version} to $remoteUrl...');
        deployed = await client.deployPackage(
          appId: app.id,
          version: package.version,
          zipBytes: package.bytes,
          filename: p.basename(package.path),
        );
      } on BackendException catch (e) {
        if (e.statusCode != 409) rethrow;
        if (!bump) {
          Logger.error('Version ${package.version} already exists.');
          Logger.hint('Re-run with --bump to publish it as the next patch '
              'version automatically.');
          return 1;
        }
        if (!build) {
          Logger.error('Version ${package.version} already exists, and --bump '
              'needs to rebuild — drop --no-build.');
          return 1;
        }
        final next = ManifestRef.bumpPatch(package.version);
        if (next == null) {
          Logger.error('Cannot bump non-semver version "${package.version}".');
          return 1;
        }
        Logger.warn('Version ${package.version} already exists — bumping to $next.');
        manifest.writeVersion(next);
        package = await _buildPackage(manifestPath, minify: minify);
        Logger.step(2, steps, 'Deploying version ${package.version} to $remoteUrl...');
        deployed = await client.deployPackage(
          appId: app.id,
          version: package.version,
          zipBytes: package.bytes,
          filename: p.basename(package.path),
        );
      }
      Logger.success('Published ${package.version} (${deployed.status ?? 'DRAFT'}).');
      ProjectCache(manifest.projectDir)
          .recordPublish(appId: app.id, version: package.version);

      // 3b. Optionally submit for review (still not a validation).
      if (submit && deployed.id != null) {
        await client.submitForReview(appId: app.id, versionId: deployed.id!);
        Logger.success('Submitted for review (IN_REVIEW).');
      } else if (submit) {
        Logger.warn('Could not submit: the deploy response carried no version id.');
      }

      // 4. Optionally bind to super-apps (idempotent; a binding is app-level,
      //    so re-publishing never needs a re-bind).
      if (superAppIds.isNotEmpty) {
        Logger.step(3, 3, 'Binding to ${superAppIds.length} super-app(s)...');
        for (final superAppId in superAppIds) {
          await client.bind(appId: app.id, superAppId: superAppId);
          Logger.success('Bound ${app.slug} to super-app $superAppId.');
        }
      }

      return 0;
    } on BackendException catch (e) {
      Logger.error(e.message +
          (e.statusCode != null ? ' (${e.statusCode})' : ''));
      if (e.body != null && e.body!.isNotEmpty) Logger.debug(e.body!);
      return 1;
    } on BundlerException catch (e) {
      Logger.error(e.message);
      return 1;
    } catch (e) {
      Logger.error('Publish failed: $e');
      return 1;
    } finally {
      client.close();
    }
  }

  /// Build the package to `dist/<slug>__<version>.zip` and return its bytes.
  Future<_Package> _buildPackage(String manifestPath,
      {required bool minify}) async {
    Logger.info('Building package...');
    final bundler = ManifestBundler(minify: minify);
    final compiled = await bundler.bundleProjectToMap(manifestPath);
    final slug = (compiled['id'] ?? 'app').toString();
    final version = (compiled['version'] ?? '0.0.0').toString();

    final result = await AssetPackager.build(
      compiledManifest: compiled,
      projectDir: p.dirname(p.absolute(manifestPath)),
      minify: minify,
    );

    final distDir = Directory(p.join(p.dirname(manifestPath), 'dist'));
    await distDir.create(recursive: true);
    final file =
        File(p.join(distDir.path, AssetPackager.packageFileName(slug, version)));
    await file.writeAsBytes(result.zipBytes, flush: true);

    return _Package(path: file.path, version: version, bytes: result.zipBytes);
  }

  /// The newest `dist/*.zip` (used with `--no-build`).
  _Package _newestPackage(String manifestPath) {
    final dist = Directory(p.join(p.dirname(manifestPath), 'dist'));
    if (!dist.existsSync()) {
      throw BundlerException(
          'No dist/ found. Build first or drop --no-build.');
    }
    final zips = dist
        .listSync()
        .whereType<File>()
        .where((f) => p.extension(f.path).toLowerCase() == '.zip')
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    if (zips.isEmpty) {
      throw BundlerException(
          'No package in dist/. Build first or drop --no-build.');
    }
    final bytes = zips.first.readAsBytesSync();
    return _Package(
      path: zips.first.path,
      version: _versionFromZip(bytes) ?? 'unknown',
      bytes: bytes,
    );
  }

  /// Read `version` from `app.json` inside a package ZIP.
  String? _versionFromZip(List<int> bytes) {
    try {
      for (final f in ZipDecoder().decodeBytes(bytes)) {
        if (f.isFile && f.name == 'app.json') {
          final json = jsonDecode(utf8.decode(f.content as List<int>))
              as Map<String, dynamic>;
          return json['version']?.toString();
        }
      }
    } catch (_) {
      // Fall through to null.
    }
    return null;
  }
}

class _Package {
  _Package({required this.path, required this.version, required this.bytes});
  final String path;
  final String version;
  final List<int> bytes;
}
