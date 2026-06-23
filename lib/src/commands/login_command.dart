import 'dart:convert';
import 'dart:io';
import 'package:args/command_runner.dart';
import 'package:http/http.dart' as http;
import '../utils/config.dart';
import '../utils/logger.dart';

class LoginCommand extends Command<int> {
  @override
  final name = 'login';

  @override
  final description = 'Authenticate with the Krom backend';

  LoginCommand() {
    argParser
      ..addFlag(
        'with-token',
        negatable: false,
        help: 'Authenticate with a Personal Access Token (krom_pat_...) '
            'instead of email/password.',
      )
      ..addOption(
        'token',
        abbr: 't',
        help: 'The Personal Access Token to use with --with-token. '
            'If omitted, it is read from stdin (input hidden).',
      )
      ..addOption('email', abbr: 'e', help: 'Your email address (deprecated)')
      ..addOption('password', abbr: 'p', help: 'Your password (deprecated)');
  }

  @override
  Future<int> run() async {
    final config = KromConfig();
    final remoteUrl = config.remoteUrl;

    if (remoteUrl == null) {
      Logger.error('Remote URL not set.');
      Logger.hint('Use "krom --set-remote=URL" to set the backend URL.');
      return 1;
    }

    final withToken = argResults!['with-token'] as bool;
    final tokenOpt = argResults!['token'] as String?;

    // A provided --token implies --with-token for convenience.
    if (withToken || tokenOpt != null) {
      return _loginWithToken(config, remoteUrl, tokenOpt);
    }

    return _loginWithPassword(config, remoteUrl);
  }

  /// Authenticate using a Personal Access Token.
  ///
  /// The PAT is validated against `GET /api/v1/access-tokens` (200 = valid)
  /// before being persisted.
  Future<int> _loginWithToken(
    KromConfig config,
    String remoteUrl,
    String? tokenOpt,
  ) async {
    var token = tokenOpt;

    if (token == null || token.isEmpty) {
      stdout.write('Personal Access Token: ');
      final hadTerminal = stdin.hasTerminal;
      if (hadTerminal) stdin.echoMode = false;
      token = stdin.readLineSync();
      if (hadTerminal) {
        stdin.echoMode = true;
        stdout.writeln();
      }
    }

    token = token?.trim();
    if (token == null || token.isEmpty) {
      Logger.error('A Personal Access Token is required.');
      return 1;
    }

    Logger.step(1, 1, 'Validating token against $remoteUrl...');

    try {
      final response = await http.get(
        Uri.parse('$remoteUrl/api/v1/access-tokens'),
        headers: {
          'accept': '*/*',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        config.setAccessToken(token);
        await config.save();
        Logger.success('Token validated. You are now logged in!');
        return 0;
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        Logger.error('Token rejected (${response.statusCode}). '
            'The Personal Access Token is invalid or expired.');
        Logger.debug(response.body);
        return 1;
      } else {
        Logger.error(
            'Token validation failed: ${response.statusCode} ${response.reasonPhrase}');
        Logger.debug(response.body);
        return 1;
      }
    } catch (e) {
      Logger.error('Connection failed: $e');
      return 1;
    }
  }

  /// Legacy email/password authentication (deprecated).
  Future<int> _loginWithPassword(KromConfig config, String remoteUrl) async {
    Logger.warn('Email/password login is deprecated.');
    Logger.hint('Prefer "krom login --with-token" with a Personal Access '
        'Token (krom_pat_...).');

    String? email = argResults!['email'];
    String? password = argResults!['password'];

    if (email == null) {
      stdout.write('Email: ');
      email = stdin.readLineSync();
    }
    if (password == null) {
      stdout.write('Password: ');
      final hadTerminal = stdin.hasTerminal;
      if (hadTerminal) stdin.echoMode = false;
      password = stdin.readLineSync();
      if (hadTerminal) {
        stdin.echoMode = true;
        stdout.writeln();
      }
    }

    if (email == null ||
        email.isEmpty ||
        password == null ||
        password.isEmpty) {
      Logger.error('Email and password are required.');
      return 1;
    }

    Logger.step(1, 1, 'Authenticating with $remoteUrl...');

    try {
      final response = await http.post(
        Uri.parse('$remoteUrl/api/v1/auth/login'),
        headers: {
          'accept': '*/*',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'password': password,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final token = data['token'] as String;
        config.setToken(token);
        await config.save();
        Logger.success('Successfully logged in!');
        return 0;
      } else {
        Logger.error(
            'Login failed: ${response.statusCode} ${response.reasonPhrase}');
        Logger.debug(response.body);
        return 1;
      }
    } catch (e) {
      Logger.error('Connection failed: $e');
      return 1;
    }
  }
}
