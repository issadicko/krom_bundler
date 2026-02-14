import 'dart:convert';
import 'dart:io';
import 'package:krom_script/krom_script.dart';
import 'package:path/path.dart' as p;

void main() async {
  final distManifestPath = p.join('example', 'dist', 'manifest.json');
  final file = File(distManifestPath);

  if (!await file.exists()) {
    print('❌ Error: $distManifestPath not found. Run bundle command first.');
    exit(1);
  }

  print('🔍 Verifying bundle content from $distManifestPath...');
  
  final json = jsonDecode(await file.readAsString());
  final pages = json['pages'] as Map<String, dynamic>;
  final components = json['components'] as Map<String, dynamic>? ?? {};

  final engine = KSEngine();
  int passCount = 0;
  int failCount = 0;

  // Verify Pages
  for (final entry in pages.entries) {
    final name = entry.key;
    final script = entry.value['script'] as String;
    
    print('\n📄 Verifying Page: $name');
    final result = await engine.load(script);
    
    if (result.success) {
      print('   ✅ Load Success');
      passCount++;
    } else {
      print('   ❌ Load FAILED:');
      print(result.errors.join('\n'));
      failCount++;
    }
  }

  // Verify Components
  for (final entry in components.entries) {
    final name = entry.key;
    final script = entry.value['script'] as String;

    print('\n🧩 Verifying Component: $name');
    final result = await engine.load(script);

    if (result.success) {
      print('   ✅ Load Success');
      passCount++;
    } else {
      print('   ❌ Load FAILED:');
      print(result.errors.join('\n'));
      failCount++;
    }
  }

  print('\n--------------------------------------------------');
  if (failCount == 0) {
    print('✅ All $passCount scripts loaded successfully!');
    exit(0);
  } else {
    print('❌ $failCount scripts failed to load.');
    exit(1);
  }
}
