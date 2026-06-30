// ============================================================
// Thème (dérivé du thème de l'app hôte), formatage monétaire,
// métadonnées de catégories et petits atomes UI réutilisables.
// (Aucune logique de page ici.)
// ============================================================

// Le runtime expose `theme` : le ColorScheme Material 3 de l'app hôte,
// aplati en chaînes "#RRGGBB" (+ brightness). On s'aligne dessus pour
// suivre la palette de l'hôte en clair ET en sombre.
let isDark = theme.brightness == "dark"

// Couleurs sémantiques « finance » (vert = revenu, rouge = dépense).
// Ce ne sont pas des rôles du thème hôte : on choisit des teintes lisibles
// sur les surfaces claires comme sombres.
let _income  = "#16A34A"
let _expense = "#DC2626"
let _warn    = "#D97706"
if (isDark) {
  _income  = "#4ADE80"
  _expense = "#F87171"
  _warn    = "#FBBF24"
}

let T = {
  // --- Structure : suit le thème de l'hôte ---
  primary:            theme.primary,
  onPrimary:          theme.onPrimary,
  primaryContainer:   theme.primaryContainer,
  onPrimaryContainer: theme.onPrimaryContainer,
  bg:                 theme.surfaceContainerLow,
  surface:            theme.surface,
  surfaceHigh:        theme.surfaceContainerHigh,
  text:               theme.onSurface,
  muted:              theme.onSurfaceVariant,
  line:               theme.outlineVariant,
  chipBg:             theme.secondaryContainer,
  onChip:             theme.onSecondaryContainer,
  // --- Sémantique finance ---
  income:  _income,
  expense: _expense,
  warn:    _warn,
  danger:  theme.error
}

// Applique une opacité (alpha hex "00".."FF") à une couleur "#RRGGBB".
// parseColor côté runtime accepte le format "#AARRGGBB".
fn alpha(hexColor, aaHex) {
  return "#" + aaHex + substring(hexColor, 1, length(hexColor))
}

// --- Catégories (emoji + couleur, par type) ------------------

let CATEGORIES = [
  { key: "food",         label: "Alimentation",  emoji: "🍔", color: "#F59E0B", kind: "expense" },
  { key: "transport",    label: "Transport",     emoji: "🚗", color: "#3B82F6", kind: "expense" },
  { key: "housing",      label: "Logement",      emoji: "🏠", color: "#8B5CF6", kind: "expense" },
  { key: "shopping",     label: "Achats",        emoji: "🛍️", color: "#EC4899", kind: "expense" },
  { key: "bills",        label: "Factures",      emoji: "⚡", color: "#0EA5E9", kind: "expense" },
  { key: "leisure",      label: "Loisirs",       emoji: "🎮", color: "#14B8A6", kind: "expense" },
  { key: "health",       label: "Santé",         emoji: "💊", color: "#EF4444", kind: "expense" },
  { key: "other",        label: "Autre",         emoji: "📦", color: "#64748B", kind: "expense" },
  { key: "salary",       label: "Salaire",       emoji: "💼", color: "#16A34A", kind: "income" },
  { key: "gift",         label: "Cadeau",        emoji: "🎁", color: "#22C55E", kind: "income" },
  { key: "refund",       label: "Remboursement", emoji: "↩️", color: "#10B981", kind: "income" },
  { key: "income_other", label: "Autre revenu",  emoji: "💰", color: "#059669", kind: "income" }
]

// Catégorie par clé (avec repli si la donnée est inconnue).
fn categoryByKey(k) {
  let found = null
  CATEGORIES.forEach(fn(c, i) {
      if (c.key == k) { found = c }
  })
  if (found == null) {
    return { key: k, label: "Autre", emoji: "•", color: T.muted, kind: "expense" }
  }
  return found
}

// Catégories d'un type donné ("expense" / "income").
fn categoriesFor(kind) {
  return CATEGORIES.filter(fn(c) { return c.kind == kind })
}

// --- Mois ----------------------------------------------------

let MONTHS = ["Janvier", "Février", "Mars", "Avril", "Mai", "Juin",
  "Juillet", "Août", "Septembre", "Octobre", "Novembre", "Décembre"]

// Nom du mois (m de 1 à 12).
fn monthName(m) {
  let i = floor(m) - 1
  if (i < 0) { return "?" }
  if (i > 11) { return "?" }
  return MONTHS[i]
}

// Décale (m, y) de `delta` mois. m de 1 à 12. Renvoie { m, y }.
fn addMonths(m, y, delta) {
  let total = y * 12 + (m - 1) + delta
  let ny = floor(total / 12)
  let nm = total - ny * 12 + 1
  return { m: nm, y: ny }
}

// --- Formatage monétaire -------------------------------------
// NB: en KromScript tous les nombres sont des doubles, donc
// toString(12) == "12.0". On reconstruit donc l'affichage à la main.

// "12.0" -> "12" (on jette la partie décimale toujours présente).
fn intDigits(d) {
  let parts = split(toString(d), ".")
  return parts[0]
}

// "1234567" -> "1 234 567" (séparateur de milliers).
fn groupDigits(ds) {
  let n = length(ds)
  if (n <= 3) { return ds }
  let out = ""
  let i = 0
  while (i < n) {
    if (i > 0) {
      if ((n - i) % 3 == 0) { out = out + " " }
    }
    out = out + substring(ds, i, i + 1)
    i = i + 1
  }
  return out
}

// Nombre -> "1 234,50 €".
fn money(n) {
  let neg = false
  let v = n
  if (v < 0) {
    neg = true
    v = -v
  }
  let cents = round(v * 100)
  let whole = floor(cents / 100)
  let frac = cents - whole * 100
  let fracStr = intDigits(frac)
  if (frac < 10) { fracStr = "0" + fracStr }
  let s = groupDigits(intDigits(whole)) + "," + fracStr + " €"
  if (neg) { s = "-" + s }
  return s
}

// Montant signé pour les lignes de transaction.
fn signedMoney(amount, type) {
  if (type == "income") { return "+ " + money(amount) }
  return "- " + money(amount)
}

// Nombre -> chaîne éditable pour un champ (sans " €", sans ".0" superflu).
// 12.0 -> "12", 12.5 -> "12.5".
fn numToInput(n) {
  let parts = split(toString(n), ".")
  if (parts.length < 2) { return parts[0] }
  if (parts[1] == "0") { return parts[0] }
  return parts[0] + "." + parts[1]
}

// Pourcentage entier borné [0..100].
fn pctInt(part, whole) {
  if (whole <= 0) { return 0 }
  let p = floor(part * 100 / whole)
  if (p < 0) { return 0 }
  if (p > 100) { return 100 }
  return p
}

// Timestamp (ms) -> "JJ/MM/AAAA".
fn fmtDate(ts) {
  return formatDate(ts, "DD/MM/YYYY")
}

// --- Atomes UI -----------------------------------------------

// Pastille ronde de couleur.
fn dot(color, sizePx) {
  return Box({ width: sizePx, height: sizePx, borderRadius: sizePx, color: color })
}

// Avatar circulaire d'une catégorie (emoji sur fond teinté de sa couleur).
fn catAvatar(cat, sizePx) {
  return Box({ width: sizePx, height: sizePx, borderRadius: sizePx, color: alpha(cat.color, "26") },
    Center(Text(cat.emoji, { fontSize: 18 }))
  )
}

// Barre de progression horizontale (pct 0..100) — piste + remplissage.
fn progressBar(pct, trackColor, fillColor, heightPx) {
  let fill = pct
  if (fill < 1) { fill = 1 }
  let rest = 100 - pct
  if (rest < 1) { rest = 1 }
  return Box({ color: trackColor, borderRadius: heightPx },
    Row({}, [
        Expanded({ flex: fill }, Box({ color: fillColor, borderRadius: heightPx, height: heightPx })),
        Expanded({ flex: rest }, Box({ height: heightPx }))
    ])
  )
}
