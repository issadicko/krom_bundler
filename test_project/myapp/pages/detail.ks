// ============================================================
// Détail d'une tâche — reçoit `args.id` depuis ui.push.
// Astuce réactivité : `tick` (Obs entier) sert de déclencheur ;
// la donnée nullable (la tâche) reste une variable locale, jamais
// stockée dans un Obs (Obs(null) est piégeux en KromScript).
// ============================================================

let taskId = ""
let tick = Obs(0)

fn refresh() {
  if (args != null) { taskId = args.id }
  tick.set(tick.value + 1)
}

fn onInit() { refresh() }
fn onShow() { refresh() }
fn back() { ui.pop() }

fn toggle() {
  if (taskId == "") { return }
  toggleTaskById(taskId)
  tick.set(tick.value + 1)
}

fn remove() {
  if (taskId == "") { return }
  deleteTaskById(taskId)
  ui.toast("Tâche supprimée")
  ui.pop()
}

fn build() {
  return Scaffold({
    appBar: AppBar({ title: "Détail", backgroundColor: T.primary }),
    backgroundColor: T.bg
  },
    Obx({ builder: "content" })
  )
}

fn content() {
  let v = tick.value          // abonne l'Obx au déclencheur
  let t = taskById(taskId)    // map ou null (variable locale)
  if (t == null) {
    return Center(Text("Tâche introuvable", { fontSize: 16, color: T.muted }))
  }

  let statusText = "À faire"
  let statusColor = T.med
  if (t.done) {
    statusText = "Terminée"
    statusColor = T.ok
  }

  let toggleLabel = "Marquer comme terminée"
  if (t.done) { toggleLabel = "Marquer comme à faire" }

  let notesText = t.notes
  if (notesText == "") { notesText = "—" }

  return ScrollView({ padding: 16 },
    Column({ spacing: 16, crossAxisAlignment: "start" }, [
      Card({ borderRadius: 16, padding: 20, color: T.surface },
        Column({ spacing: 12, crossAxisAlignment: "start" }, [
          Text(t.title, { fontSize: 22, fontWeight: "bold", color: T.text }),
          Row({ spacing: 8, crossAxisAlignment: "center" }, [
            dot(priorityColor(t.priority), 10),
            Text("Priorité " + priorityLabel(t.priority), { fontSize: 13, color: T.muted })
          ]),
          chip(statusText, statusColor)
        ])
      ),
      Card({ borderRadius: 16, padding: 20, color: T.surface },
        Column({ spacing: 8, crossAxisAlignment: "start" }, [
          Text("Notes", { fontSize: 13, fontWeight: "bold", color: T.muted }),
          Text(notesText, { fontSize: 15, color: T.text })
        ])
      ),
      Button(toggleLabel, { onTap: "toggle", color: T.primary, fullWidth: true, icon: "check" }),
      Button("Supprimer", { onTap: "remove", color: T.danger, fullWidth: true, icon: "delete" })
    ])
  )
}
