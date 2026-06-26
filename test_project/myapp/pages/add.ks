// ============================================================
// Nouvelle tâche — formulaire (titre, notes, priorité).
// ============================================================

let title = ""
let notes = ""
let priority = Obs("medium")

fn onTitle(v) { title = v }
fn onNotes(v) { notes = v }
fn setPriority(p) { priority.set(p) }
fn cancel() { ui.pop() }

fn save() {
  if (title == "") {
    ui.toast("Le titre est requis")
    return
  }
  addTask(title, notes, priority.value)
  ui.toast("Tâche ajoutée")
  ui.pop()
}

fn build() {
  return Scaffold({
    appBar: AppBar({ title: "Nouvelle tâche", backgroundColor: T.primary }),
    backgroundColor: T.bg
  },
    ScrollView({ padding: 16 },
      Column({ spacing: 16, crossAxisAlignment: "start" }, [
        Card({ borderRadius: 16, padding: 16, color: T.surface },
          Column({ spacing: 14, crossAxisAlignment: "start" }, [
            Text("Détails", { fontSize: 14, fontWeight: "bold", color: T.text }),
            TextField({ labelText: "Titre", value: title, onChange: "onTitle" }),
            TextField({ labelText: "Notes (optionnel)", value: notes, onChange: "onNotes" })
          ])
        ),
        Text("Priorité", { fontSize: 14, fontWeight: "bold", color: T.text }),
        Obx({ builder: "priorityRow" }),
        Button("Enregistrer", { onTap: "save", color: T.primary, fullWidth: true, icon: "save" }),
        Button("Annuler", { onTap: "cancel", variant: "text", color: T.muted, fullWidth: true })
      ])
    )
  )
}

fn priorityRow() {
  let p = priority.value
  return Row({ spacing: 10 }, [
    prioOption("Basse", "low", p),
    prioOption("Moyenne", "medium", p),
    prioOption("Haute", "high", p)
  ])
}

fn prioOption(label, value, current) {
  let col = priorityColor(value)
  let bg = T.surface
  let border = "#E5E7EB"
  let fg = T.text
  let dotCol = col
  if (value == current) {
    bg = col
    fg = "white"
    border = col
    dotCol = "white"
  }
  return Expanded({ flex: 1 },
    InkWell({ onTap: "setPriority", arg: value, borderRadius: 12 },
      Box({ color: bg, borderRadius: 12, padding: 14, borderColor: border, borderWidth: 1 },
        Row({ spacing: 8, mainAxisAlignment: "center", crossAxisAlignment: "center" }, [
          dot(dotCol, 10),
          Text(label, { fontSize: 13, fontWeight: "600", color: fg })
        ])
      )
    )
  )
}
