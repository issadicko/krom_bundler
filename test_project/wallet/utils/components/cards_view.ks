// ============================================================
// Onglet Cards : carte de crédit (dégradé) + actions (gel, réglages).
// ============================================================
@use "../ui.ks"
@use "../state.ks"
@use "./shared.ks"

fn cardsTab() {
  return tabScreen("Your cards", [
      cardTile(),
      Obx({ builder: "cardActions" })
  ])
}

fn cardTile() {
  return Box({ gradient: { colors: ["#111827", "#374151"], angle: 135 }, borderRadius: 22, padding: 22 },
    Column({ crossAxisAlignment: "start", spacing: 22 }, [
        Row({ mainAxisAlignment: "spaceBetween", crossAxisAlignment: "center" }, [
            Text("Wallet", { fontSize: 15, fontWeight: "600", color: "#FFFFFF" }),
            Text("VISA", { fontSize: 17, fontWeight: "bold", color: "#FFFFFF" })
        ]),
        Text("••••  ••••  ••••  2675", { fontSize: 18, fontWeight: "600", color: alpha("#FFFFFF", "F2") }),
        Row({ mainAxisAlignment: "spaceBetween", crossAxisAlignment: "end" }, [
            Column({ crossAxisAlignment: "start", spacing: 2 }, [
                Text("CARD HOLDER", { fontSize: 10, color: alpha("#FFFFFF", "99") }),
                Text("A. TURNER", { fontSize: 14, fontWeight: "600", color: "#FFFFFF" })
            ]),
            Column({ crossAxisAlignment: "start", spacing: 2 }, [
                Text("EXPIRES", { fontSize: 10, color: alpha("#FFFFFF", "99") }),
                Text("08/27", { fontSize: 14, fontWeight: "600", color: "#FFFFFF" })
            ])
        ])
    ])
  )
}

fn cardActions() {
  let frozen = freeze.value
  let stateLabel = "Active"
  if (frozen) { stateLabel = "Gelée" }
  return listCard(Column({ spacing: 6 }, [
        Row({ mainAxisAlignment: "spaceBetween", crossAxisAlignment: "center" }, [
            Column({ crossAxisAlignment: "start", spacing: 2 }, [
                Text("Geler la carte", { fontSize: 15, color: T.text }),
                Text(stateLabel, { fontSize: 12, color: T.muted })
            ]),
            Switch({ value: frozen, onChanged: "toggleFreeze", activeColor: T.text })
        ]),
        Divider({ height: 1, color: T.line }),
        settingRow("payment", "Réglages de la carte"),
        settingRow("lock", "Code PIN")
  ]))
}

fn toggleFreeze(v) { freeze.set(v) }
