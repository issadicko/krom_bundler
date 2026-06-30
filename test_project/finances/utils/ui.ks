// ============================================================
// Thème, formatage monétaire et métadonnées de catégories.
// (Aucune logique de page ici — atomes réutilisables.)
// ============================================================

let T = {
  primary: "#2563EB",
  primaryDark: "#1E40AF",
  bg: "#F1F5F9",
  surface: "#FFFFFF",
  text: "#0F172A",
  muted: "#64748B",
  line: "#E2E8F0",
  income: "#16A34A",
  incomeBg: "#DCFCE7",
  expense: "#DC2626",
  expenseBg: "#FEE2E2",
  danger: "#DC2626",
  chipBg: "#EFF6FF"
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

// Timestamp (ms) -> "JJ/MM/AAAA".
fn fmtDate(ts) {
  return formatDate(ts, "DD/MM/YYYY")
}

// --- Atomes UI -----------------------------------------------

// Pastille ronde de couleur.
fn dot(color, sizePx) {
  return Box({ width: sizePx, height: sizePx, borderRadius: sizePx, color: color })
}

// Avatar circulaire d'une catégorie (emoji sur fond coloré).
fn catAvatar(cat, sizePx) {
  return Box({ width: sizePx, height: sizePx, borderRadius: sizePx, color: cat.color },
    Center(Text(cat.emoji, { fontSize: 18 }))
  )
}
