// ============================================================
// Thème hôte (injecté) + helpers de mise en page.
// ============================================================
let T = {
  bg: theme.surface,
  card: theme.surfaceContainerHigh,
  cardAlt: theme.surfaceContainerHighest,
  text: theme.onSurface,
  muted: theme.onSurfaceVariant,
  primary: theme.primary,
  onPrimary: theme.onPrimary,
  ink: theme.onSurface,
  line: theme.outlineVariant,
  danger: theme.error
}

// Carte de section.
fn card(child) {
  return Box({ color: T.card, borderRadius: 18, padding: 16, margin: { bottom: 14 } }, child)
}

// Titre de section (petit, en majuscules visuelles).
fn sectionTitle(t) {
  return Text(t, { fontSize: 12, fontWeight: "bold", color: T.muted })
}

// Ligne label / contrôle.
fn field(label, child) {
  return Column({ crossAxisAlignment: "stretch", spacing: 8 }, [
      Text(label, { fontSize: 14, fontWeight: "600", color: T.text }),
      child
  ])
}

// Petite étiquette de résultat réactif.
fn resultChip(txt) {
  return Box({ color: T.cardAlt, borderRadius: 10, padding: { left: 10, right: 10, top: 6, bottom: 6 } },
    Text(txt, { fontSize: 13, color: T.muted })
  )
}
