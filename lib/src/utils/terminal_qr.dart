import 'dart:io';

import 'package:qr/qr.dart';

/// Renders [data] as a QR code for the terminal (the `krom dev` scan target).
///
/// Half-block rendering: each output row carries two module rows via `▀`,
/// with explicit ANSI foreground/background colors so the code stays
/// dark-on-light regardless of the terminal theme (pure glyph rendering would
/// invert on dark terminals, which some scanners reject). Includes the
/// standard quiet zone. Returns an empty string when [data] can't be encoded.
String terminalQr(String data) {
  final QrImage image;
  try {
    final code = QrCode.fromData(
      data: data,
      errorCorrectLevel: QrErrorCorrectLevel.M,
    );
    image = QrImage(code);
  } catch (_) {
    return '';
  }

  const quiet = 2;
  final size = image.moduleCount + quiet * 2;
  bool dark(int x, int y) {
    final mx = x - quiet, my = y - quiet;
    if (mx < 0 || my < 0 || mx >= image.moduleCount || my >= image.moduleCount) {
      return false; // quiet zone
    }
    return image.isDark(my, mx);
  }

  // fg paints the TOP module of the `▀` glyph, bg paints the BOTTOM one.
  const black = 30, white = 97, bgBlack = 40, bgWhite = 107;
  final buf = StringBuffer();
  for (var y = 0; y < size; y += 2) {
    for (var x = 0; x < size; x++) {
      final top = dark(x, y);
      final bottom = y + 1 < size && dark(x, y + 1);
      buf.write('\x1B[${top ? black : white};${bottom ? bgBlack : bgWhite}m▀');
    }
    buf.writeln('\x1B[0m');
  }
  return buf.toString();
}

/// The machine's LAN IPv4 (the address a phone on the same network can
/// reach), or null when only loopback/link-local interfaces exist. Private
/// ranges are preferred over anything else.
Future<String?> lanIPv4() async {
  try {
    final interfaces = await NetworkInterface.list(
      includeLoopback: false,
      type: InternetAddressType.IPv4,
    );
    final all = [for (final i in interfaces) ...i.addresses]
        .where((a) => !a.isLoopback && !a.address.startsWith('169.254.'))
        .toList();
    if (all.isEmpty) return null;
    bool private(InternetAddress a) =>
        a.address.startsWith('192.168.') ||
        a.address.startsWith('10.') ||
        RegExp(r'^172\.(1[6-9]|2\d|3[01])\.').hasMatch(a.address);
    return (all.where(private).firstOrNull ?? all.first).address;
  } catch (_) {
    return null;
  }
}
