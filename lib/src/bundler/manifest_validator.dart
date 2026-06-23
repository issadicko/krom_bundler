import 'bundler.dart';

/// Validates the structure of a Krom mini-app manifest, including the
/// TCMPP-style fields: `window`, `tabBar`, `permissions`/`scopes`,
/// `networkTimeout` and `subpackages` (分包).
///
/// Validation is non-fatal field by field: every problem is collected and
/// reported together via a single [BundlerException] with explicit,
/// actionable messages.
///
/// Usage:
/// ```dart
/// ManifestValidator.validate(manifest); // throws on the first batch of errors
/// ```
class ManifestValidator {
  ManifestValidator._();

  /// Recognised `navigationBarTextStyle` values (TCMPP).
  static const _navBarTextStyles = {'black', 'white'};

  /// Validate [manifest]. Throws a [BundlerException] aggregating every
  /// problem found. Returns normally when the manifest is valid.
  ///
  /// [pageKeys] are the known page identifiers (from `manifest['pages']`).
  /// When omitted they are derived from the manifest itself; passing them
  /// explicitly lets callers validate against the post-processing page set.
  static void validate(
    Map<String, dynamic> manifest, {
    Set<String>? pageKeys,
  }) {
    final errors = <String>[];
    final pages = pageKeys ??
        ((manifest['pages'] as Map?)?.keys.map((e) => e.toString()).toSet() ??
            const <String>{});

    _validateWindow(manifest['window'], errors);
    _validateTabBar(manifest['tabBar'], pages, errors);
    _validatePermissions(manifest, errors);
    _validateNetworkTimeout(manifest['networkTimeout'], errors);
    _validateSubpackages(manifest['subpackages'] ?? manifest['subPackages'],
        pages, errors);

    if (errors.isNotEmpty) {
      final bullets = errors.map((e) => '  - $e').join('\n');
      throw BundlerException(
          'Manifest validation failed (${errors.length} '
          'error${errors.length == 1 ? '' : 's'}):\n$bullets');
    }
  }

  // --- window ---------------------------------------------------------------

  static void _validateWindow(dynamic window, List<String> errors) {
    if (window == null) return;
    if (window is! Map) {
      errors.add('"window" must be an object.');
      return;
    }

    const allowed = {
      'navigationBarTitleText',
      'navigationBarBackgroundColor',
      'navigationBarTextStyle',
    };
    for (final key in window.keys) {
      if (!allowed.contains(key)) {
        errors.add('"window.$key" is not a recognised property. '
            'Allowed: ${allowed.join(', ')}.');
      }
    }

    final title = window['navigationBarTitleText'];
    if (title != null && title is! String) {
      errors.add('"window.navigationBarTitleText" must be a string.');
    }

    final bg = window['navigationBarBackgroundColor'];
    if (bg != null) {
      if (bg is! String) {
        errors.add('"window.navigationBarBackgroundColor" must be a string.');
      } else if (!_isHexColor(bg)) {
        errors.add('"window.navigationBarBackgroundColor" must be a hex '
            'color like "#ffffff" (got "$bg").');
      }
    }

    final textStyle = window['navigationBarTextStyle'];
    if (textStyle != null) {
      if (textStyle is! String || !_navBarTextStyles.contains(textStyle)) {
        errors.add('"window.navigationBarTextStyle" must be one of '
            '${_navBarTextStyles.join(', ')} (got "$textStyle").');
      }
    }
  }

  // --- tabBar ---------------------------------------------------------------

  static void _validateTabBar(
    dynamic tabBar,
    Set<String> pages,
    List<String> errors,
  ) {
    if (tabBar == null) return;
    if (tabBar is! Map) {
      errors.add('"tabBar" must be an object with a "list" array.');
      return;
    }

    final list = tabBar['list'];
    if (list == null) {
      errors.add('"tabBar.list" is required when "tabBar" is present.');
      return;
    }
    if (list is! List) {
      errors.add('"tabBar.list" must be an array.');
      return;
    }
    if (list.isEmpty) {
      errors.add('"tabBar.list" must contain at least one item.');
      return;
    }
    if (list.length < 2 || list.length > 5) {
      // TCMPP allows 2..5 tabs; warn via error to stay explicit.
      errors.add('"tabBar.list" must contain between 2 and 5 items '
          '(got ${list.length}).');
    }

    for (var i = 0; i < list.length; i++) {
      final item = list[i];
      final where = 'tabBar.list[$i]';
      if (item is! Map) {
        errors.add('"$where" must be an object.');
        continue;
      }

      final pagePath = item['pagePath'];
      if (pagePath == null) {
        errors.add('"$where.pagePath" is required.');
      } else if (pagePath is! String) {
        errors.add('"$where.pagePath" must be a string.');
      } else if (!pages.contains(pagePath)) {
        errors.add('"$where.pagePath" refers to "$pagePath" which is not '
            'declared in "pages" (known pages: '
            '${pages.isEmpty ? '<none>' : pages.join(', ')}).');
      }

      final text = item['text'];
      if (text == null) {
        errors.add('"$where.text" is required.');
      } else if (text is! String) {
        errors.add('"$where.text" must be a string.');
      }

      final iconPath = item['iconPath'];
      if (iconPath != null && iconPath is! String) {
        errors.add('"$where.iconPath" must be a string.');
      }
    }
  }

  // --- permissions / scopes -------------------------------------------------

  static void _validatePermissions(
    Map<String, dynamic> manifest,
    List<String> errors,
  ) {
    // Accept both legacy `permissions` and TCMPP `scopes`. When given as a
    // map (scope -> { desc }) we validate the TCMPP shape. A bare list of
    // strings is also accepted for backward compatibility.
    for (final key in const ['permissions', 'scopes']) {
      final value = manifest[key];
      if (value == null) continue;

      if (value is List) {
        // Legacy: list of scope names.
        for (var i = 0; i < value.length; i++) {
          if (value[i] is! String) {
            errors.add('"$key[$i]" must be a string scope name.');
          }
        }
        continue;
      }

      if (value is! Map) {
        errors.add('"$key" must be an object mapping a scope to '
            '{ "desc": ... }, or an array of scope names.');
        continue;
      }

      for (final entry in value.entries) {
        final scope = entry.key;
        final cfg = entry.value;
        final where = '$key.$scope';
        if (cfg is! Map) {
          errors.add('"$where" must be an object like { "desc": "..." }.');
          continue;
        }
        final desc = cfg['desc'];
        if (desc == null) {
          errors.add('"$where.desc" is required (a human-readable reason).');
        } else if (desc is! String) {
          errors.add('"$where.desc" must be a string.');
        }
      }
    }
  }

  // --- networkTimeout -------------------------------------------------------

  static void _validateNetworkTimeout(dynamic timeout, List<String> errors) {
    if (timeout == null) return;
    if (timeout is! Map) {
      errors.add('"networkTimeout" must be an object.');
      return;
    }

    const allowed = {'request', 'uploadFile', 'downloadFile', 'connectSocket'};
    for (final entry in timeout.entries) {
      final key = entry.key;
      final value = entry.value;
      if (!allowed.contains(key)) {
        errors.add('"networkTimeout.$key" is not a recognised property. '
            'Allowed: ${allowed.join(', ')}.');
        continue;
      }
      if (value is! num || value <= 0) {
        errors.add('"networkTimeout.$key" must be a positive number of '
            'milliseconds (got "$value").');
      }
    }
  }

  // --- subpackages (分包) ----------------------------------------------------

  static void _validateSubpackages(
    dynamic subpackages,
    Set<String> pages,
    List<String> errors,
  ) {
    if (subpackages == null) return;
    if (subpackages is! List) {
      errors.add('"subpackages" must be an array of '
          '{ "root": ..., "pages": [...] }.');
      return;
    }

    final seenRoots = <String>{};
    for (var i = 0; i < subpackages.length; i++) {
      final pkg = subpackages[i];
      final where = 'subpackages[$i]';
      if (pkg is! Map) {
        errors.add('"$where" must be an object.');
        continue;
      }

      final root = pkg['root'];
      if (root == null) {
        errors.add('"$where.root" is required.');
      } else if (root is! String || root.isEmpty) {
        errors.add('"$where.root" must be a non-empty string.');
      } else if (!seenRoots.add(root)) {
        errors.add('"$where.root" duplicates another subpackage root '
            '("$root").');
      }

      final pkgPages = pkg['pages'];
      if (pkgPages == null) {
        errors.add('"$where.pages" is required.');
      } else if (pkgPages is! List) {
        errors.add('"$where.pages" must be an array of page paths.');
      } else if (pkgPages.isEmpty) {
        errors.add('"$where.pages" must contain at least one page.');
      } else {
        for (var j = 0; j < pkgPages.length; j++) {
          if (pkgPages[j] is! String) {
            errors.add('"$where.pages[$j]" must be a string.');
          }
        }
      }
    }
  }

  // --- helpers --------------------------------------------------------------

  static bool _isHexColor(String value) {
    return RegExp(r'^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$')
        .hasMatch(value);
  }
}
