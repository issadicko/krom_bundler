// ============================================================
// Wallet — thème (dérivé de l'hôte), format USD, atomes UI.
// Look « néobanque » : surfaces claires, accent neutre haut-contraste
// (inverseSurface = « noir »), une touche de dégradé.
// ============================================================

let isDark = theme.brightness == "dark"

let _income = "#16A34A"
if (isDark) { _income = "#4ADE80" }

let T = {
  bg:          theme.surfaceContainerLow,    // fond d'écran (gris très clair)
  card:        theme.surfaceContainerLowest,  // cartes (le plus clair)
  cardAlt:     theme.surfaceContainerHigh,    // cartes sur fond blanc (sheet)
  text:        theme.onSurface,
  muted:       theme.onSurfaceVariant,
  line:        theme.outlineVariant,
  ink:         theme.inverseSurface,          // accent « noir » haut-contraste
  onInk:       theme.onInverseSurface,
  primary:     theme.primary,
  income:      _income,
  danger:      theme.error
}

// Opacité (alpha hex "00".."FF") sur "#RRGGBB" -> "#AARRGGBB".
fn alpha(hexColor, aaHex) {
  return "#" + aaHex + substring(hexColor, 1, length(hexColor))
}

// --- Format monétaire USD ("$12,386.40") ---------------------
// Tous les nombres sont des doubles en KromScript.

fn intDigits(d) {
  let parts = split(toString(d), ".")
  return parts[0]
}

// "1234567" -> "1,234,567"
fn commaGroup(ds) {
  let n = length(ds)
  if (n <= 3) { return ds }
  let out = ""
  let i = 0
  while (i < n) {
    if (i > 0) {
      if ((n - i) % 3 == 0) { out = out + "," }
    }
    out = out + substring(ds, i, i + 1)
    i = i + 1
  }
  return out
}

// Nombre -> "<sym>1,234.50" (négatif -> "-<sym>1,234.50").
fn fmtMoney(n, sym) {
  let neg = n < 0
  let v = n
  if (neg) { v = -v }
  let cents = round(v * 100)
  let whole = floor(cents / 100)
  let frac = cents - whole * 100
  let fracStr = intDigits(frac)
  if (frac < 10) { fracStr = "0" + fracStr }
  let s = sym + commaGroup(intDigits(whole)) + "." + fracStr
  if (neg) { s = "-" + s }
  return s
}

// Nombre -> "$1,234.50".
fn usd(n) {
  return fmtMoney(n, "$")
}

// Montant signé pour une ligne d'opération ("+$50.00" / "-$21.50").
fn signedUsd(n) {
  if (n >= 0) { return "+" + usd(n) }
  return usd(n)
}

// --- Atomes UI -----------------------------------------------

// Avatar circulaire (emoji sur fond teinté).
fn avatarCircle(emoji, color, size) {
  return Box({ width: size, height: size, borderRadius: size, color: alpha(color, "26") },
    Center(Text(emoji, { fontSize: size * 0.42 }))
  )
}

// Petite carte (fond clair, coins arrondis).
fn card(child) {
  return Box({ color: T.cardAlt, borderRadius: 20, padding: 16 }, child)
}

// Ligne label (gauche) / valeur-widget (droite).
fn detailRow(label, valueWidget) {
  return Row({ mainAxisAlignment: "spaceBetween", crossAxisAlignment: "center", spacing: 12 }, [
      Text(label, { fontSize: 14, color: T.muted }),
      valueWidget
  ])
}
