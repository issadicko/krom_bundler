import 'dart:io';
import 'package:krom_bundler/krom_bundler.dart';
import 'package:path/path.dart' as p;

void main() async {
  final exampleDir = p.dirname(Platform.script.toFilePath());
  final manifestPath = p.join(exampleDir, 'manifest.json');
  
  print('📦 Bundling Example Project...');
  print('--------------------------------------------------');

  // 1. Bundle WITHOUT Optimization
  print('\n[1] Bundling WITHOUT Optimization:');
  final bundlerNoOpt = ManifestBundler(enableOptimizer: false);
  final startNoOpt = DateTime.now();
  final resultNoOpt = await bundlerNoOpt.bundleProject(manifestPath);
  final durationNoOpt = DateTime.now().difference(startNoOpt);
  
  final sizeNoOpt = resultNoOpt.length;
  print('    ✅ Completed in ${durationNoOpt.inMilliseconds}ms');
  print('    📊 Output Size: $sizeNoOpt bytes');
  
  // 2. Bundle WITH Optimization
  print('\n[2] Bundling WITH Optimization (Tree Shaking, Inlining, CP, DCE):');
  final bundlerOpt = ManifestBundler(enableOptimizer: true);
  final startOpt = DateTime.now();
  final resultOpt = await bundlerOpt.bundleProject(manifestPath);
  final durationOpt = DateTime.now().difference(startOpt);
  
  final sizeOpt = resultOpt.length;
  print('    ✅ Completed in ${durationOpt.inMilliseconds}ms');
  print('    📊 Output Size: $sizeOpt bytes');
  
  // 3. Comparison
  print('\n--------------------------------------------------');
  print('RESULTS:');
  final reduction = sizeNoOpt - sizeOpt;
  final percent = (reduction / sizeNoOpt * 100).toStringAsFixed(1);
  
  print('📉 Size Reduction: $reduction bytes ($percent%)');
}
