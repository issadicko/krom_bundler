/// String-literal-aware minifier for bundled KromScript.
///
/// Strips line comments and collapses whitespace, but never touches the
/// contents of string/template literals — URLs like `https://…`, operators and
/// punctuation inside quotes must survive verbatim. A naive regex pass would,
/// for example, eat `//dummyjson.com"` as a line comment and corrupt the source.
String minifyKromSource(String source) {
  final out = StringBuffer();
  final code = StringBuffer();

  void flushCode() {
    out.write(_minifyCode(code.toString()));
    code.clear();
  }

  final n = source.length;
  var i = 0;
  while (i < n) {
    final ch = source[i];

    // Line comment (outside strings only): drop to end of line.
    if (ch == '/' && i + 1 < n && source[i + 1] == '/') {
      i += 2;
      while (i < n && source[i] != '\n') {
        i++;
      }
      continue;
    }

    // String or template literal: copy verbatim up to the matching quote so its
    // content is never minified (honouring backslash escapes).
    if (ch == '"' || ch == "'" || ch == '`') {
      flushCode();
      out.write(ch);
      i++;
      while (i < n) {
        final c = source[i];
        if (c == '\\' && i + 1 < n) {
          out.write(c);
          out.write(source[i + 1]);
          i += 2;
          continue;
        }
        out.write(c);
        i++;
        if (c == ch) break;
      }
      continue;
    }

    code.write(ch);
    i++;
  }
  flushCode();

  return out.toString().trim();
}

/// Collapses whitespace and trims spaces around operators/punctuation for a span
/// of code that contains no string literals or comments.
String _minifyCode(String span) {
  // NB: String.replaceAll treats the replacement as a literal ($1 is NOT a
  // backreference), so the group-preserving passes must use replaceAllMapped.
  var result = span.replaceAll(RegExp(r'\s+'), ' ');
  result = result.replaceAllMapped(RegExp(r'\s*([{}()\[\],;:])\s*'), (m) => m[1]!);
  result = result.replaceAllMapped(RegExp(r'\s*([=+\-*/<>!&|])\s*'), (m) => m[1]!);
  return result;
}
