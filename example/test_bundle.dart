import 'dart:io';
import 'dart:convert';
import 'package:krom_bundler/krom_bundler.dart';

void main() async {
  // Bundle without optimizer to see raw output
  final bundler = ManifestBundler(enableOptimizer: false, minify: false);
  final result = await bundler.bundleProject('manifest.json');
  
  // Parse the JSON to get the home page script
  final manifest = jsonDecode(result);
  final homeScript = manifest['pages']['home']['script'] as String;
  
  print('=== Home page script (lines 115-135) ===');
  final lines = homeScript.split('\n');
  for (int i = 114; i < 140 && i < lines.length; i++) {
    print('${i+1}: ${lines[i]}');
  }
  
  print('\n=== Full script length: ${lines.length} lines ===');
  
  // Save to file for inspection
  await File('output_raw.ks').writeAsString(homeScript);
  print('Saved to output_raw.ks');
}
