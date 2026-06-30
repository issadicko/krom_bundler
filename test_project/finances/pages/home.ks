// ============================================================
// Accueil — solde total, résumé du mois, liste des transactions.
// ============================================================
@use "../utils/ui.ks"
@use "../utils/store.ks"

let tx = List([])
let filter = Obs("all")

fn refresh() {
  let loaded = loadTx()
  tx.clear()
  tx.addAll(loaded)
}

// Recharge à l'ouverture et à chaque retour sur la page.
fn onInit() { refresh() }
fn onShow() { refresh() }

// --- Actions ---
fn setFilter(f) { filter.set(f) }
fn goAdd() { ui.push("add") }
fn goStats() { ui.push("stats") }
fn onOpen(id) { ui.push("detail", { id: id }) }

// Transactions à afficher : plus récentes d'abord, filtrées par type.
fn visibleTx() {
  let f = filter.value
  let all = reverse(tx.value)
  if (f == "income") {
    return all.filter(fn(t) { return t.type == "income" })
  }
  if (f == "expense") {
    return all.filter(fn(t) { return t.type == "expense" })
  }
  return all
}

// --- UI ---
fn build() {
  return Scaffold({
      appBar: AppBar({
          title: "Mes Finances",
          backgroundColor: T.primary,
          actions: [ IconButton("info", { onTap: "goStats" }) ]
      }),
      backgroundColor: T.bg
    },
    Column({}, [
        Obx({ builder: "summary" }),
        Obx({ builder: "filters" }),
        Expanded({ flex: 1 }, Obx({ builder: "list" })),
        bottomAdd()
    ])
  )
}

fn summary() {
  let items = tx.value
  let bal = balance(items)
  let mItems = monthItems(items)
  let inc = sumByType(mItems, "income")
  let exp = sumByType(mItems, "expense")
  return Box({ color: T.primary, padding: 20 },
    Column({ crossAxisAlignment: "start", spacing: 16 }, [
        Column({ crossAxisAlignment: "start", spacing: 2 }, [
            Text("Solde total", { fontSize: 13, color: "#DBEAFE" }),
            Text(money(bal), { fontSize: 30, fontWeight: "bold", color: "white" })
        ]),
        Row({ spacing: 12 }, [
            Expanded({ flex: 1 }, summaryPill("Revenus du mois", money(inc), T.incomeBg, T.income)),
            Expanded({ flex: 1 }, summaryPill("Dépenses du mois", money(exp), T.expenseBg, T.expense))
        ])
    ])
  )
}

fn summaryPill(label, value, bg, fg) {
  return Box({ color: bg, borderRadius: 14, padding: 12 },
    Column({ crossAxisAlignment: "start", spacing: 4 }, [
        Text(label, { fontSize: 12, color: fg }),
        Text(value, { fontSize: 16, fontWeight: "bold", color: fg })
    ])
  )
}

fn filters() {
  let f = filter.value
  return Box({ color: T.surface, padding: 12 },
    Row({ spacing: 8, mainAxisAlignment: "center" }, [
        filterChip("Tout", "all", f),
        filterChip("Revenus", "income", f),
        filterChip("Dépenses", "expense", f)
    ])
  )
}

fn filterChip(label, value, current) {
  let bg = T.chipBg
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
  let items = visibleTx()
  if (items.length == 0) {
    return emptyState()
  }
  let rows = items.map(fn(t) { return txRow(t) })
  return ScrollView({ padding: 16 },
    Column({ spacing: 10 }, rows)
  )
}

fn txRow(t) {
  let cat = categoryByKey(t.category)
  let amountColor = T.expense
  let sign = "- "
  if (t.type == "income") {
    amountColor = T.income
    sign = "+ "
  }
  return InkWell({ onTap: "onOpen", arg: t.id, borderRadius: 16 },
    Box({ color: T.surface, borderRadius: 16, padding: 12 },
      Row({ crossAxisAlignment: "center", spacing: 12 }, [
          catAvatar(cat, 44),
          Expanded({ flex: 1 },
            Column({ crossAxisAlignment: "start", spacing: 3 }, [
                Text(cat.label, { fontSize: 15, fontWeight: "600", color: T.text }),
                Text(rowSubtitle(t), { fontSize: 12, color: T.muted })
            ])
          ),
          Text(sign + money(t.amount), { fontSize: 15, fontWeight: "bold", color: amountColor })
      ])
    )
  )
}

fn rowSubtitle(t) {
  let d = fmtDate(t.date)
  if (t.note == "") { return d }
  return d + " · " + t.note
}

fn emptyState() {
  return Center(
    Column({ crossAxisAlignment: "center", mainAxisAlignment: "center", spacing: 10 }, [
        Text("💸", { fontSize: 56 }),
        Text("Aucune transaction", { fontSize: 18, fontWeight: "600", color: T.muted }),
        Text("Ajoutez votre première opération", { fontSize: 13, color: "#94A3B8" })
    ])
  )
}

fn bottomAdd() {
  return Box({ color: T.surface, padding: 14 },
    Button("Nouvelle transaction", { onTap: "goAdd", color: T.primary, fullWidth: true, icon: "add" })
  )
}
