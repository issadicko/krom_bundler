// ============================================================
// Composants partagés entre écrans (coquilles, lignes, chips).
// ============================================================
@use "../ui.ks"

// Coquille d'un onglet : titre + liste de blocs, scrollable, padding bas
// pour la barre flottante.
fn tabScreen(title, items) {
  let kids = [ Text(title, { fontSize: 24, fontWeight: "bold", color: T.text }) ]
  items.forEach(fn(w, i) { kids.add(w) })
  return ScrollView({ padding: { left: 16, right: 16, top: 16, bottom: 110 } },
    Column({ crossAxisAlignment: "stretch", spacing: 16 }, kids)
  )
}

fn listCard(child) {
  return Box({ color: T.card, borderRadius: 20, padding: 16 }, child)
}

fn settingRow(icon, label) {
  return InkWell({ onTap: "noop", borderRadius: 12 },
    Box({ padding: { left: 0, right: 0, top: 8, bottom: 8 } },
      Row({ crossAxisAlignment: "center", spacing: 12 }, [
          Box({ width: 36, height: 36, borderRadius: 18, color: T.cardAlt },
            Center(Icon(icon, { size: 18, color: T.text }))
          ),
          Expanded({ flex: 1 }, Text(label, { fontSize: 15, color: T.text })),
          Icon("chevron_right", { size: 18, color: T.muted })
      ])
    )
  )
}

fn chip(label) {
  return Box({ color: T.cardAlt, borderRadius: 14, padding: { left: 12, right: 8, top: 6, bottom: 6 } },
    Row({ spacing: 2, crossAxisAlignment: "center" }, [
        Text(label, { fontSize: 13, fontWeight: "600", color: T.text }),
        Icon("chevron_right", { size: 16, color: T.muted })
    ])
  )
}

// En-tête de bottom sheet : bouton de fermeture (la poignée + fond blanc
// sont fournis par le runtime).
fn sheetHeader() {
  return Row({ mainAxisAlignment: "start" }, [
      InkWell({ onTap: "closeSheet", borderRadius: 20 },
        Box({ width: 40, height: 40, borderRadius: 20, color: T.cardAlt },
          Center(Icon("close", { size: 20, color: T.text }))
        )
      )
  ])
}

// Ligne d'opération (avatar + nom/heure + montant signé). Tap -> détail.
fn opRow(t) {
  let col = T.text
  if (t.amount >= 0) { col = T.income }
  return InkWell({ onTap: "openTx", arg: t.id, borderRadius: 14 },
    Row({ crossAxisAlignment: "center", spacing: 12 }, [
        avatarCircle(t.emoji, t.color, 42),
        Expanded({ flex: 1 },
          Column({ crossAxisAlignment: "start", spacing: 2 }, [
              Text(t.name, { fontSize: 15, fontWeight: "600", color: T.text }),
              Text(t.time, { fontSize: 12, color: T.muted })
          ])
        ),
        Text(signedUsd(t.amount), { fontSize: 15, fontWeight: "bold", color: col })
    ])
  )
}
