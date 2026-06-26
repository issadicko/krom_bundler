// ============================================================
// Accueil — liste des tâches (réactive + persistée).
// ============================================================

let tasks = List([])
let filter = Obs("all")

fn refresh() {
  let loaded = loadTasks()
  tasks.clear()
  tasks.addAll(loaded)
}

// Recharge à l'ouverture et à chaque retour sur la page.
fn onInit() { refresh() }
fn onShow() { refresh() }

fn visibleTasks() {
  let f = filter.value
  let all = tasks.value
  if (f == "active") {
    return all.filter(fn(t) { return !t.done })
  }
  if (f == "done") {
    return all.filter(fn(t) { return t.done })
  }
  return all
}

// --- Actions ---
fn goAdd() { ui.push("add") }
fn goAbout() { ui.push("about") }
fn setFilter(f) { filter.set(f) }
fn onOpen(id) { ui.push("detail", { id: id }) }

fn onToggle(id) {
  toggleTaskById(id)
  refresh()
}

fn onDelete(id) {
  deleteTaskById(id)
  refresh()
  ui.toast("Tâche supprimée")
}

// --- UI ---
fn build() {
  return Scaffold({
    appBar: AppBar({
      title: "Mes Tâches",
      backgroundColor: T.primary,
      actions: [ IconButton("info", { onTap: "goAbout" }) ]
    }),
    backgroundColor: T.bg
  },
    Column({}, [
      Obx({ builder: "banner" }),
      Obx({ builder: "filters" }),
      Expanded({ flex: 1 }, Obx({ builder: "list" })),
      bottomAdd()
    ])
  )
}

fn banner() {
  let all = tasks.value
  let total = all.length
  let done = countDone(all)
  let pct = 0
  if (total > 0) { pct = floor(done * 100 / total) }
  return Box({ color: T.primary, padding: 20 },
    Row({ mainAxisAlignment: "spaceBetween", crossAxisAlignment: "center" }, [
      Column({ crossAxisAlignment: "start", spacing: 2 }, [
        Text("Bonjour 👋", { fontSize: 13, color: "#E9DDFF" }),
        Text(total + " tâche(s) · " + done + " faite(s)", { fontSize: 18, fontWeight: "bold", color: "white" })
      ]),
      Box({ color: T.primaryDark, borderRadius: 30, padding: 14 },
        Text(pct + "%", { fontSize: 16, fontWeight: "bold", color: "white" })
      )
    ])
  )
}

fn filters() {
  let f = filter.value
  return Box({ color: T.surface, padding: 12 },
    Row({ spacing: 8, mainAxisAlignment: "center" }, [
      filterChip("Toutes", "all", f),
      filterChip("À faire", "active", f),
      filterChip("Terminées", "done", f)
    ])
  )
}

fn filterChip(label, value, current) {
  let bg = "#EDE9F6"
  let fg = T.primary
  if (value == current) {
    bg = T.primary
    fg = "white"
  }
  return InkWell({ onTap: "setFilter", arg: value, borderRadius: 20 },
    Box({ color: bg, borderRadius: 20, padding: 10 },
      Text(label, { fontSize: 13, fontWeight: "600", color: fg })
    )
  )
}

fn list() {
  let items = visibleTasks()
  if (items.length == 0) {
    return emptyState()
  }
  let rows = items.map(fn(t) { return taskRow(t) })
  return ScrollView({ padding: 16 },
    Column({ spacing: 12 }, rows)
  )
}

fn taskRow(task) {
  let titleColor = T.text
  let checkColor = "#CBD5E1"
  if (task.done) {
    titleColor = T.muted
    checkColor = T.ok
  }
  return Box({ color: T.surface, borderRadius: 16, padding: 4 },
    Row({ crossAxisAlignment: "center" }, [
      InkWell({ onTap: "onToggle", arg: task.id, borderRadius: 30 },
        Box({ padding: 12 }, Icon("check", { size: 26, color: checkColor }))
      ),
      Expanded({ flex: 1 },
        InkWell({ onTap: "onOpen", arg: task.id },
          Box({ padding: 12 },
            Column({ crossAxisAlignment: "start", spacing: 4 }, [
              Text(task.title, { fontSize: 16, fontWeight: "600", color: titleColor }),
              Row({ spacing: 8, crossAxisAlignment: "center" }, [
                dot(priorityColor(task.priority), 8),
                Text(priorityLabel(task.priority), { fontSize: 12, color: T.muted })
              ])
            ])
          )
        )
      ),
      InkWell({ onTap: "onDelete", arg: task.id, borderRadius: 30 },
        Box({ padding: 14 }, Icon("delete", { size: 20, color: T.danger }))
      )
    ])
  )
}

fn emptyState() {
  return Center(
    Column({ crossAxisAlignment: "center", mainAxisAlignment: "center", spacing: 10 }, [
      Icon("check", { size: 64, color: "#CFC9DE" }),
      Text("Aucune tâche ici", { fontSize: 18, fontWeight: "600", color: T.muted }),
      Text("Appuyez sur « Nouvelle tâche »", { fontSize: 13, color: "#9CA3AF" })
    ])
  )
}

fn bottomAdd() {
  return Box({ color: T.surface, padding: 14 },
    Button("Nouvelle tâche", { onTap: "goAdd", color: T.primary, fullWidth: true, icon: "add" })
  )
}
