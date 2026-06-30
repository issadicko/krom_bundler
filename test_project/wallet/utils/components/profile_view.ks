// ============================================================
// Onglet Profile : en-tête utilisateur + réglages.
// ============================================================
@use "../ui.ks"
@use "./shared.ks"

fn meTab() {
  return tabScreen("Profile", [
      profileHeader(),
      listCard(Column({ spacing: 2 }, [
            settingRow("person", "Informations personnelles"),
            settingRow("lock", "Sécurité"),
            settingRow("notifications", "Notifications"),
            settingRow("info", "Aide & support")
      ])),
      InkWell({ onTap: "noop", borderRadius: 16 },
        Box({ color: T.card, borderRadius: 16, padding: 16 },
          Center(Text("Se déconnecter", { fontSize: 15, fontWeight: "600", color: T.danger }))
        )
      )
  ])
}

fn profileHeader() {
  return listCard(Row({ crossAxisAlignment: "center", spacing: 14 }, [
        avatarCircle("🧑", "#6366F1", 56),
        Expanded({ flex: 1 },
          Column({ crossAxisAlignment: "start", spacing: 2 }, [
              Text("Alexa Turner", { fontSize: 17, fontWeight: "bold", color: T.text }),
              Text("alexa.turner@email.com", { fontSize: 13, color: T.muted })
          ])
        )
  ]))
}
