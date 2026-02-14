import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:krom_bundler/src/bundler/manifest_bundler.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Bundler Tree Shaking Integration', () {
    final tempDir = Directory('test_temp_bundler');

    setUp(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
      await tempDir.create();
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('removes unused functions when optimized', () async {
      // 1. Create a simple project
      final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
      await manifestFile.writeAsString('''
{
  "id": "test-app",
  "name": "Test App",
  "version": "1.0.0",
  "entry": "home",
  "pages": {
    "home": {
      "name": "Home",
      "source": "home.ks"
    }
  }
}
''');

      final homeFile = File(p.join(tempDir.path, 'home.ks'));
      await homeFile.writeAsString('''
fn unusedFunction() {
  return "I should be removed"
}

fn helper() {
  return "I am used"
}

fn build() {
  return helper()
}
''');

      // 2. Run build command with optimization
      final bundler = ManifestBundler(enableOptimizer: true);
      final resultJson = await bundler.bundleProject(manifestFile.path);
      
      // 3. Verify output
      final manifest = jsonDecode(resultJson);
      final homeScript = manifest['pages']['home']['script'] as String;
      
      print('Bundled script:\n$homeScript');
      
      // Should contain used function
      expect(homeScript, contains('fn helper()'));
      expect(homeScript, contains('fn build()'));
      
      // Should NOT contain unused function
      expect(homeScript, isNot(contains('fn unusedFunction()')));
      expect(homeScript, isNot(contains('I should be removed')));
    });

    test('retains functions when optimization is disabled', () async {
      // 1. Create a simple project
      final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
      await manifestFile.writeAsString('''
{
  "id": "test-app-no-opt",
  "name": "Test App No Opt",
  "version": "1.0.0",
  "entry": "home",
  "pages": {
    "home": {
      "name": "Home",
      "source": "home.ks"
    }
  }
}
''');

      final homeFile = File(p.join(tempDir.path, 'home.ks'));
      await homeFile.writeAsString('''
fn unusedFunction() {
  return "I should be kept"
}

fn build() {
  return 1
}
''');

      // 2. Run build command WITHOUT optimization
      final bundler = ManifestBundler(enableOptimizer: false);
      final resultJson = await bundler.bundleProject(manifestFile.path);
      
      // 3. Verify output
      final manifest = jsonDecode(resultJson);
      final homeScript = manifest['pages']['home']['script'] as String;
      
      // Should contain unused function
      expect(homeScript, contains('fn unusedFunction()'));
    });
  });
}
