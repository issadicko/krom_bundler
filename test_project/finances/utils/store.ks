// ============================================================
// Données : transactions persistées en JSON dans le storage local
// (clé "finances_tx"). Chaque page a son propre moteur, donc l'état
// est partagé uniquement via le storage, rechargé dans onInit/onShow.
//
// Forme d'une transaction :
//   { id, type: "income"|"expense", amount, category, note, date }
// ============================================================
@use "./ui.ks"  // expenseByCategory s'appuie sur categoriesFor (ui.ks)

fn loadTx() {
  let raw = storage.getItem("finances_tx")
  if (raw == null) { return [] }
  let parsed = jsonParse(raw)
  if (parsed == null) { return [] }
  return parsed
}

fn persistTx(items) {
  storage.setItem("finances_tx", jsonStringify(items))
}

fn addTx(type, amount, category, note) {
  let items = loadTx()
  items.add({
      id: randomUUID(),
      type: type,
      amount: amount,
      category: category,
      note: note,
      date: now()
  })
  persistTx(items)
}

fn txById(id) {
  let items = loadTx()
  let found = null
  items.forEach(fn(t, i) {
      if (t.id == id) { found = t }
  })
  return found
}

fn deleteTxById(id) {
  let items = loadTx()
  let out = []
  items.forEach(fn(t, i) {
      if (t.id != id) { out.add(t) }
  })
  persistTx(out)
}

// --- Agrégations ---------------------------------------------

fn sumByType(items, type) {
  let total = 0
  items.forEach(fn(t, i) {
      if (t.type == type) { total = total + t.amount }
  })
  return total
}

fn balance(items) {
  return sumByType(items, "income") - sumByType(items, "expense")
}

// Transactions du mois calendaire courant.
fn monthItems(items) {
  let m = month()
  let y = year()
  let out = []
  items.forEach(fn(t, i) {
      if (month(t.date) == m) {
        if (year(t.date) == y) { out.add(t) }
      }
  })
  return out
}

// Dépenses agrégées par catégorie : [{ key, label, emoji, color, total }].
// On itère sur les catégories connues (pas de dictionnaire dynamique).
fn expenseByCategory(items) {
  let out = []
  categoriesFor("expense").forEach(fn(c, i) {
      let total = 0
      items.forEach(fn(t, j) {
          if (t.type == "expense") {
            if (t.category == c.key) { total = total + t.amount }
          }
      })
      if (total > 0) {
        out.add({ key: c.key, label: c.label, emoji: c.emoji, color: c.color, total: total })
      }
  })
  return out
}
