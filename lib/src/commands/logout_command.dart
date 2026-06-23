import 'package:args/command_runner.dart';
import '../utils/config.dart';
import '../utils/logger.dart';

/// Logout command - clears stored credentials.
class LogoutCommand extends Command<int> {
  @override
  final name = 'logout';

  @override
  final description = 'Clear stored credentials';

  @override
  Future<int> run() async {
    final config = KromConfig();

    if (!config.isAuthenticated) {
      Logger.info('You are not logged in.');
      return 0;
    }

    config.clearTokens();
    await config.save();
    Logger.success('Logged out. Credentials cleared.');
    return 0;
  }
}
