import 'package:args/command_runner.dart';
import '../utils/config.dart';
import '../utils/logger.dart';

/// Whoami command - reports the current authentication state.
class WhoamiCommand extends Command<int> {
  @override
  final name = 'whoami';

  @override
  final description = 'Show the current authentication status';

  @override
  Future<int> run() async {
    final config = KromConfig();
    final remoteUrl = config.remoteUrl;

    Logger.keyValue('Remote', remoteUrl ?? '(not set)');

    if (config.isAuthenticated) {
      final method = (config.accessToken != null &&
              config.accessToken!.isNotEmpty)
          ? 'Personal Access Token'
          : 'legacy session (email/password)';
      Logger.success('Authenticated');
      Logger.keyValue('Method', method);
    } else {
      Logger.warn('Not authenticated.');
      Logger.hint('Run "krom login --with-token" to authenticate.');
    }

    if (remoteUrl == null) {
      Logger.hint('Use "krom --set-remote=URL" to set the backend URL.');
    }

    return 0;
  }
}
