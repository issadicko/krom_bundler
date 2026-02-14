import 'dart:io';
import 'package:krom_bundler/krom_bundler.dart';
import 'package:path/path.dart' as p;

void main() async {
  final tempDir = Directory('test_temp_syntax_error');
  if (await tempDir.exists()) await tempDir.delete(recursive: true);
  await tempDir.create();

  try {
    print('🚨 Testing Syntax Error Detection...');
    
    // Create invalid file
    final manifestFile = File(p.join(tempDir.path, 'manifest.json'));
    await manifestFile.writeAsString('''
{
  "id": "error-app",
  "name": "Error App",
  "version": "1.0.0",
  "entry": "home",
  "pages": {
    "home": { "source": "home.ks" }
  }
}
''');

    await File(p.join(tempDir.path, 'home.ks')).writeAsString('''
fn build() {
  let x = ; // Syntax error!
  return x
}
''');

    final bundler = ManifestBundler(enableOptimizer: true);
    await bundler.bundleProject(manifestFile.path);
    
    // Should NOT reach here
    print('🚨 TEST FAILED: Bundling succeeded despite syntax error');
    exit(1);

  } catch (e) {
    print('✅ Bundling FAILED as expected:');
    print(e);
    // Verify it is the correct error
    if (e.toString().contains('Syntax Error')) {
      print('✅ Error message contains "Syntax Error"');
    } else {
      print('⚠️ Unexpected error message');
      exit(1);
    }
  } finally {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  }
}
