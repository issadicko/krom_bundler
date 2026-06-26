// ============================================================
// À propos — infos app + appareil (device.systemInfo) + asset.
// `ready` (Obs bool) déclenche le rendu ; `sysInfo` reste une
// map locale (on évite Obs(null)).
// ============================================================

let sysInfo = {}
let ready = Obs(false)

fn onInit() {
  sysInfo = device.systemInfo()
  ready.set(true)
}

fn clearAll() {
  clearTasks()
  ui.toast("Toutes les tâches ont été supprimées")
}

fn build() {
  return Scaffold({
      appBar: AppBar({ title: "À propos", backgroundColor: T.primary }),
      backgroundColor: T.bg
    },
    ScrollView({ padding: 20 },
      Column({ spacing: 16, crossAxisAlignment: "center" }, [
          Center(Image("assets/images/qr-proxy.png", { width: 150, height: 150 })),
          Text("Mes Tâches", { fontSize: 22, fontWeight: "bold", color: T.text }),
          Text("v1.0.0 · propulsé par KromLang", { fontSize: 13, color: T.muted }),
          Card({ borderRadius: 16, padding: 16, color: T.surface },
            Obx({ builder: "deviceCard" })
          ),
          Button("Tout effacer", { onTap: "clearAll", color: T.danger, fullWidth: true, icon: "delete" })
      ])
    )
  )
}

fn deviceCard() {
  let r = ready.value
  if (r == false) {
    return Text("Chargement…", { fontSize: 13, color: T.muted })
  }
  return Column({ spacing: 12, crossAxisAlignment: "start" }, [
      Text("Appareil", { fontSize: 13, fontWeight: "bold", color: T.muted }),
      infoRow("Plateforme", sysInfo.platform),
      infoRow("Système", sysInfo.osVersion),
      infoRow("Modèle", sysInfo.model)
  ])
}

fn infoRow(k, v) {
  let val = v
  if (val == null) { val = "—" }
  return Row({ mainAxisAlignment: "spaceBetween" }, [
      Text(k, { fontSize: 13, color: T.muted }),
      Text(val, { fontSize: 13, fontWeight: "600", color: T.text })
  ])
}
