// ============================================================
// Base API + thème + petits helpers d'UI réutilisables.
// ============================================================

let BASE = "https://dummyjson.com"

let T = {
  primary: "#2563EB",
  primaryLight: "#DBEAFE",
  bg: "#F1F5F9",
  surface: "#FFFFFF",
  text: "#0F172A",
  muted: "#64748B"
}

// Pilule de catégorie.
fn chip(label) {
  return Box({ color: T.primaryLight, borderRadius: 20, padding: 6 },
    Text(label, { fontSize: 11, fontWeight: "600", color: T.primary })
  )
}

// Ligne de métadonnées : ❤ likes · N vues.
fn metaRow(likes, views) {
  return Row({ spacing: 8, crossAxisAlignment: "center" }, [
      Icon("favorite", { size: 14, color: "#EF4444" }),
      Text("" + likes, { fontSize: 12, color: T.muted }),
      Text("·  " + views + " vues", { fontSize: 12, color: T.muted })
  ])
}

// Tronque un contenu long pour l'aperçu de liste.
fn excerpt(s) {
  if (s == null) { return "" }
  if (length(s) <= 130) { return s }
  return substring(s, 0, 130) + "…"
}

fn loadingView() {
  return Center(CircularProgressIndicator({}))
}

fn errorView() {
  return Center(
    Column({ crossAxisAlignment: "center", mainAxisAlignment: "center", spacing: 10 }, [
        Icon("warning", { size: 48, color: "#EF4444" }),
        Text("Échec du chargement", { fontSize: 16, fontWeight: "600", color: T.muted }),
        Text("Vérifie ta connexion réseau", { fontSize: 13, color: "#94A3B8" })
    ])
  )
}
