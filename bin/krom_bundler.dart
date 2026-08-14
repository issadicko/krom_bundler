import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:krom_bundler/krom_bundler.dart';

const String kromVersion = '0.4.0';

void main(List<String> arguments) async {
  Logger.version = kromVersion;

  // Load config
  final config = KromConfig();
  await config.load();

  // Handle --set-remote globally
  for (var i = 0; i < arguments.length; i++) {
    if (arguments[i].startsWith('--set-remote=')) {
      final url = arguments[i].substring('--set-remote='.length);
      config.setRemoteUrl(url);
      await config.save();
      Logger.success('Remote URL set to: $url');
      exit(0);
    }
  }

  // Handle --version before CommandRunner
  if (arguments.contains('--version') || arguments.contains('-v')) {
    print('krom $kromVersion');
    exit(0);
  }

  // Handle --verbose globally
  if (arguments.contains('--verbose')) {
    Logger.verbose = true;
    arguments = arguments.where((a) => a != '--verbose').toList();
  }

  // `krom` sans rien : l'autre moment où quelqu'un découvre l'outil. Le
  // bandeau ne sort pas sur `--help` d'une sous-commande, où l'on cherche une
  // option précise et pas une présentation.
  if (arguments.isEmpty) {
    Logger.banner();
  }

  final runner = CommandRunner<int>(
    'krom',
    'Krom CLI v$kromVersion — Bundle and serve KromScript projects',
  )
    ..argParser
        .addFlag('version', abbr: 'v', negatable: false, help: 'Print version')
    ..argParser
        .addFlag('verbose', negatable: false, help: 'Enable verbose output')
    ..addCommand(InitCommand())
    ..addCommand(DevCommand())
    ..addCommand(BuildCommand())
    ..addCommand(BundleCommand())
    ..addCommand(LoginCommand())
    ..addCommand(LogoutCommand())
    ..addCommand(WhoamiCommand())
    ..addCommand(DeployCommand())
    ..addCommand(PublishCommand())
    ..addCommand(BindCommand())
    ..addCommand(LinkCommand())
    ..addCommand(SuperAppsCommand())
    ..addCommand(BindingsCommand());

  try {
    final result = await runner.run(arguments);
    exit(result ?? 0);
  } on UsageException catch (e) {
    Logger.error(e.message);
    Logger.hint(e.usage);
    exit(64);
  } catch (e) {
    Logger.error('$e');
    exit(1);
  }
}
