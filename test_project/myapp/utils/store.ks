// ============================================================
// Données : tâches persistées en JSON dans le storage local.
// Chaque page a son propre moteur, donc l'état est partagé
// uniquement via le storage (rechargé dans onInit/onShow).
// ============================================================

fn loadTasks() {
  let raw = storage.getItem("tasks")
  if (raw == null) { return [] }
  let parsed = jsonParse(raw)
  if (parsed == null) { return [] }
  return parsed
}

fn persist(items) {
  storage.setItem("tasks", jsonStringify(items))
}

fn addTask(title, notes, priority) {
  let items = loadTasks()
  items.add({
      id: randomUUID(),
      title: title,
      notes: notes,
      priority: priority,
      done: false,
      createdAt: now()
  })
  persist(items)
}

fn taskById(id) {
  let items = loadTasks()
  let found = null
  items.forEach(fn(t, i) {
      if (t.id == id) { found = t }
  })
  return found
}

// Réécrit la liste avec le champ `done` inversé pour la tâche ciblée.
fn toggleTaskById(id) {
  let items = loadTasks()
  let out = []
  items.forEach(fn(t, i) {
      if (t.id == id) {
        out.add({
            id: t.id,
            title: t.title,
            notes: t.notes,
            priority: t.priority,
            done: !t.done,
            createdAt: t.createdAt
        })
      } else {
        out.add(t)
      }
  })
  persist(out)
}

fn deleteTaskById(id) {
  let items = loadTasks()
  let out = []
  items.forEach(fn(t, i) {
      if (t.id != id) { out.add(t) }
  })
  persist(out)
}

fn clearTasks() {
  storage.removeItem("tasks")
}

fn countDone(items) {
  let n = 0
  items.forEach(fn(t, i) {
      if (t.done) { n = n + 1 }
  })
  return n
}
