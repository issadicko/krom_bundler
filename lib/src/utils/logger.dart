import 'dart:io';

/// Log levels for the Krom CLI logger.
enum LogLevel { debug, info, success, warn, error }

/// Structured logger with ANSI colors for the Krom CLI.
///
/// Provides consistent, colorful output across all commands
/// with support for timers, progress indicators, and structured sections.
class Logger {
  static bool verbose = false;
  static bool _useColor = stdout.hasTerminal;

  // ANSI color codes
  static const _reset = '\x1B[0m';
  static const _bold = '\x1B[1m';
  static const _dim = '\x1B[2m';
  static const _red = '\x1B[31m';
  static const _green = '\x1B[32m';
  static const _yellow = '\x1B[33m';
  static const _blue = '\x1B[34m';
  static const _magenta = '\x1B[35m';
  static const _cyan = '\x1B[36m';
  static const _white = '\x1B[37m';
  static const _gray = '\x1B[90m';

  static String _c(String color, String text) {
    return _useColor ? '$color$text$_reset' : text;
  }

  // --- Core log methods ---

  static void debug(String message) {
    if (verbose) {
      stderr.writeln(_c(_gray, '  [debug] $message'));
    }
  }

  static void info(String message) {
    stdout.writeln(_c(_blue, '  ℹ ') + message);
  }

  static void success(String message) {
    stdout.writeln(_c(_green, '  ✓ ') + message);
  }

  static void warn(String message) {
    stderr.writeln(_c(_yellow, '  ⚠ ') + message);
  }

  static void error(String message) {
    stderr.writeln(_c(_red, '  ✗ ') + message);
  }

  static void hint(String message) {
    stdout.writeln(_c(_dim, '    → $message'));
  }

  // --- Structured output ---

  static void header(String title) {
    stdout.writeln('');
    stdout.writeln(_c('$_bold$_cyan', '  $title'));
    stdout.writeln(_c(_dim, '  ${'─' * title.length}'));
  }

  static void newline() => stdout.writeln('');

  static void step(int current, int total, String message) {
    final progress = _c(_dim, '[$current/$total]');
    stdout.writeln('  $progress $message');
  }

  // --- Key/Value display ---

  static void keyValue(String key, String value) {
    stdout.writeln('  ${_c(_dim, '$key:')} $value');
  }

  // --- File operations ---

  static void fileCreated(String path) {
    stdout.writeln('  ${_c(_green, '+')} $path');
  }

  static void fileChanged(String path) {
    stdout.writeln('  ${_c(_yellow, '~')} $path');
  }

  // --- Timer ---

  static Stopwatch startTimer() => Stopwatch()..start();

  static String formatDuration(Duration d) {
    if (d.inSeconds >= 60) {
      return '${d.inMinutes}m ${d.inSeconds % 60}s';
    }
    if (d.inMilliseconds >= 1000) {
      return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
    }
    return '${d.inMilliseconds}ms';
  }

  // --- File size ---

  static String formatSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '$bytes B';
  }

  // --- Build summary ---

  static void buildSummary({
    required Duration duration,
    required int pages,
    int? components,
    int? outputSize,
    String? outputPath,
  }) {
    newline();
    stdout.writeln(_c('$_bold$_green', '  Build Summary'));
    stdout.writeln(_c(_dim, '  ${'─' * 13}'));
    keyValue('  Duration', formatDuration(duration));
    keyValue('  Pages', '$pages');
    if (components != null && components > 0) {
      keyValue('  Components', '$components');
    }
    if (outputSize != null) {
      keyValue('  Output size', formatSize(outputSize));
    }
    if (outputPath != null) {
      keyValue('  Output', outputPath);
    }
    newline();
  }

  // --- Error reporting ---

  static void bundleError({
    required String message,
    String? file,
    int? line,
    int? column,
    String? suggestion,
  }) {
    newline();
    stderr.writeln(_c('$_bold$_red', '  Error'));
    stderr.writeln(_c(_dim, '  ${'─' * 5}'));
    stderr.writeln('  ${_c(_red, message)}');
    if (file != null) {
      final location = StringBuffer(file);
      if (line != null) location.write(':$line');
      if (column != null) location.write(':$column');
      stderr.writeln('  ${_c(_dim, 'at')} $location');
    }
    if (suggestion != null) {
      stderr.writeln('  ${_c(_cyan, '→')} $suggestion');
    }
    newline();
  }

  // --- Server status ---

  static void serverStarted({
    required String host,
    required int port,
    required String manifestPath,
  }) {
    newline();
    stdout.writeln(_c('$_bold$_magenta', '  Krom Dev Server'));
    stdout.writeln(_c(_dim, '  ${'─' * 16}'));
    keyValue('  URL', _c('$_bold$_white', 'http://$host:$port'));
    keyValue('  Manifest', manifestPath);
    keyValue('  Hot Reload', _c(_green, 'enabled'));
    newline();
    stdout.writeln(_c(_dim, '  Watching for changes... Press Ctrl+C to stop.'));
    newline();
  }
}
