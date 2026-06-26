// ============================================================
// Thème + atomes UI réutilisables (sans logique de page).
// ============================================================

let T = {
  primary: "#6750A4",
  primaryDark: "#4F378B",
  bg: "#F4F2F8",
  surface: "#FFFFFF",
  text: "#1C1B1F",
  muted: "#6B7280",
  danger: "#EF4444",
  ok: "#22C55E",
  low: "#60A5FA",
  med: "#F59E0B",
  high: "#EF4444"
}

fn priorityColor(p) {
  if (p == "high") { return T.high }
  if (p == "low") { return T.low }
  return T.med
}

fn priorityLabel(p) {
  if (p == "high") { return "Haute" }
  if (p == "low") { return "Basse" }
  return "Moyenne"
}

// Pastille ronde de couleur.
fn dot(color, sizePx) {
  return Box({ width: sizePx, height: sizePx, borderRadius: sizePx, color: color })
}

// Badge / pilule colorée.
fn chip(label, color) {
  return Box({ color: color, borderRadius: 20, padding: 8 },
    Text(label, { fontSize: 12, fontWeight: "600", color: "white" })
  )
}
