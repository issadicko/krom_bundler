import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:krom_bundler/src/bundler/manifest_bundler.dart';
import 'package:path/path.dart' as p;

void main() {
  group('Bundler Optimization Pipeline', () {
    final tempDir = Directory('test_temp_opt_pipeline');

    setUp(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
      await tempDir.create();
    });

    tearDown(() async {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    });

    test('applies all optimizations: Inlining, CP, DCE, Tree Shaking', () async {
      // 1. Create a simple project
      final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
      await manifestFile.writeAsString('''
{
  "id": "test-opt",
  "name": "Test Opt",
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
fn add(a, b) {
  return a + b
}

fn unused() {
  return "remove me"
}

fn build() {
  let x = add(10, 20)     // Inlining: 10+20. CP: 30.
  let y = 50              // Constant
  let z = x + y           // CP: 30 + 50 -> 80
  
  let unused_var = 999    // DCE should remove this
  
  return z                // Result: return 80
}
''');

      // 2. Run build command with optimization ENABLED
      final bundler = ManifestBundler(enableOptimizer: true);
      final resultJson = await bundler.bundleProject(manifestFile.path);
      
      // 3. Verify output
      final manifest = jsonDecode(resultJson);
      final homeScript = manifest['pages']['home']['script'] as String;
      
      print('Bundled optimized script:\n$homeScript');
      
      // Tree Shaking
      expect(homeScript, isNot(contains('fn unused()')));
      
      // Inlining & CP -> Expected to see '80' directly in return or variable
      // Since 'z' is returned, and 'z' folds to 80.
      // 'x' and 'y' might be removed if their values are folded into usage.
      // The output AST printer should print something like:
      // fn build() {
      //   return 80
      // }
      // Or:
      // fn build() {
      //   let z = 80
      //   return z
      // }
      // But CP should propagate 80 to return statement too?
      // Wait, my CP propagates constants to usages.
      // If 'z' is constant 80. 'return z' becomes 'return 80'.
      // Then 'let z = 80' becomes unused.
      // Then DCE removes 'let z'.
      // So final output should be minimal.
      
      expect(homeScript, contains('return 80'));
      
      // DCE
      expect(homeScript, isNot(contains('unused_var')));
      expect(homeScript, isNot(contains('let x =')));
      expect(homeScript, isNot(contains('let y =')));
      // 'add' function might remain if Tree Shaker runs BEFORE Inlining. 
      // If 'add' was inlined everywhere, it is still "used" according to Tree Shaker pass 1.
      // The current pipeline order is: TreeShaking -> Inlining -> CP -> DCE.
      // So 'add' will remain because at step 1 it is used.
      // To remove 'add', we'd need another TreeShaking pass at the end.
      // Or run Inlining before Tree Shaking.
      // But Inlining usually increases code size, so maybe we want to shake first?
      // Standard is: Shake, Inline, Shake again?
      // For now, I expect 'add' to be present.
      expect(homeScript, contains('fn add(a, b)'));
    });
  });
}
