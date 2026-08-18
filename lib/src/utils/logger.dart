import 'dart:io';

import 'ansi.dart';
import 'banner.dart';

/// Log levels for the Krom CLI logger.
enum LogLevel { debug, info, success, warn, error }

/// Structured logger with ANSI colors for the Krom CLI.
///
/// Provides consistent, colorful output across all commands
/// with support for timers, progress indicators, and structured sections.
class Logger {
  static bool verbose = false;

  /// Version affichée sous le bandeau, posée au démarrage par `bin/`.
  ///
  /// La constante reste dans `bin/krom_bundler.dart` : le test de cohérence et
  /// le job CI de release la cherchent là, et une seconde déclaration dans
  /// `lib/` serait exactement la dérive qu'ils existent pour empêcher.
  static String version = '';

  // Alias locaux : tout le fichier écrit déjà `_c(_dim, …)`, et la palette vit
  // désormais dans Ansi, partagée avec les questions interactives.
  static const _bold = Ansi.bold;
  static const _dim = Ansi.dim;
  static const _red = Ansi.red;
  static const _green = Ansi.green;
  static const _yellow = Ansi.yellow;
  static const _blue = Ansi.blue;
  static const _magenta = Ansi.magenta;
  static const _cyan = Ansi.cyan;
  static const _white = Ansi.white;
  static const _gray = Ansi.gray;
  static const _accent = Ansi.accent;

  /// Force le mode couleur — réservé aux tests, qui comparent la sortie brute.
  static set useColorForTests(bool value) => Ansi.enabled = value;

  static String _c(String color, String text) => Ansi.paint(color, text);

  // --- Signature ---

  /// Le mot KROM, la version et une ligne de description.
  ///
  /// Ne s'affiche que sur un terminal en couleurs : redirigé dans un fichier ou
  /// dans un pipe, un bandeau de blocs n'est que du bruit à filtrer. Les
  /// commandes qui l'appellent le font avant tout travail, jamais entre deux
  /// étapes — c'est une entrée en matière, pas une décoration.
  static void banner({String? subtitle}) {
    if (!Ansi.enabled) return;
    newline();
    for (final row in kKromWordmark) {
      stdout.writeln('  ${_c(_accent, row)}');
    }
    final tagline = subtitle ?? 'Bundle and serve KromScript projects';
    stdout
        .writeln('  ${_c(_dim, 'v$version'.padRight(10))}${_c(_dim, tagline)}');
    newline();
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

  // --- Encadrés ---

  /// Un encadré titré, ses lignes alignées sur la clé la plus longue.
  ///
  /// Les valeurs arrivent **sans couleur** : la bordure se calcule sur la
  /// largeur visible, et une séquence ANSI déjà posée par l'appelant la
  /// fausserait — un cadre décalé d'autant de caractères qu'il y a de codes.
  /// La mise en avant se demande par [highlight], pas en pré-colorant.
  static void panel(
    String title,
    List<(String, String)> rows, {
    String color = _cyan,
    String? highlight,
    String? footer,
  }) {
    if (rows.isEmpty) return;
    final keyWidth =
        rows.map((r) => r.$1.length).reduce((a, b) => a > b ? a : b);
    final bodyWidth = rows.map((r) => keyWidth + 2 + r.$2.length).followedBy([
      title.length + 2,
      if (footer != null) footer.length
    ]).reduce((a, b) => a > b ? a : b);

    final head = '╭─ $title ${'─' * (bodyWidth - title.length - 1)}╮';
    newline();
    stdout.writeln('  ${_c(color, head)}');
    for (final (key, value) in rows) {
      final label = _c(_dim, '$key:'.padRight(keyWidth + 1));
      final shown = key == highlight ? _c('$_bold$_white', value) : value;
      final padding = ' ' * (bodyWidth - keyWidth - 2 - value.length);
      stdout.writeln(
          '  ${_c(color, '│')} $label $shown$padding ${_c(color, '│')}');
    }
    if (footer != null) {
      stdout.writeln(
          '  ${_c(color, '│')} ${_c(_dim, footer.padRight(bodyWidth))} ${_c(color, '│')}');
    }
    stdout.writeln('  ${_c(color, '╰${'─' * (bodyWidth + 2)}╯')}');
    newline();
  }

  // --- Build summary ---

  static void buildSummary({
    required Duration duration,
    required int pages,
    int? components,
    int? outputSize,
    String? outputPath,
  }) {
    panel(
      'Build',
      [
        ('Duration', formatDuration(duration)),
        ('Pages', '$pages'),
        if (components != null && components > 0) ('Components', '$components'),
        if (outputSize != null) ('Output size', formatSize(outputSize)),
        if (outputPath != null) ('Output', outputPath),
      ],
      color: _green,
    );
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
    // L'URL est ce qu'on vient chercher des yeux pour la copier : elle est la
    // seule ligne en gras de l'encadré.
    panel(
      'Krom Dev Server',
      [
        ('URL', 'http://$host:$port'),
        ('Manifest', manifestPath),
        ('Hot reload', 'enabled'),
      ],
      color: _magenta,
      highlight: 'URL',
      footer: 'Watching for changes… Ctrl+C to stop.',
    );
  }
}
