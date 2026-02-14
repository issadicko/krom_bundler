import 'package:args/command_runner.dart';
import 'package:krom_bundler/krom_bundler.dart';

void main(List<String> arguments) async {
  final runner = CommandRunner<int>(
    'krom',
    'Krom Bundler CLI - Bundle and serve KromLang projects',
  )
    ..addCommand(InitCommand())
    ..addCommand(DevCommand())
    ..addCommand(BuildCommand())
    ..addCommand(BundleCommand());

  try {
    final result = await runner.run(arguments);
    if (result != null && result != 0) {
      throw Exception('Command failed with code $result');
    }
  } on UsageException catch (e) {
    print(e);
  }
}
