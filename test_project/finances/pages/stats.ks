// ============================================================
// Statistiques — bilan d'un mois (navigable) + répartition des
// dépenses par catégorie (barres proportionnelles).
// ============================================================
@use "../utils/ui.ks"
@use "../utils/store.ks"

let tick = Obs(0)
let monthOffset = Obs(0)

fn onInit() { tick.set(tick.value + 1) }
fn onShow() { tick.set(tick.value + 1) }
fn back() { ui.pop() }
fn prevMonth() { monthOffset.set(monthOffset.value - 1) }
fn nextMonth() { monthOffset.set(monthOffset.value + 1) }

fn periodMY() {
  return addMonths(month(), year(), monthOffset.value)
}

fn build() {
  return Scaffold({
      appBar: AppBar({ title: "Statistiques", backgroundColor: T.primary }),
      backgroundColor: T.bg
    },
    Obx({ builder: "content" })
  )
}

fn content() {
  let v = tick.value
  let off = monthOffset.value
  let p = periodMY()
  let items = monthItemsFor(loadTx(), p.m, p.y)
  let inc = sumByType(items, "income")
  let exp = sumByType(items, "expense")
  let cats = sortByTotalDesc(expenseByCategory(items))

  let blocks = [ monthHeader(p, inc, exp) ]

  if (cats.length == 0) {
    blocks.add(Card({ borderRadius: 16, padding: 24, color: T.surface },
        Center(Text("Aucune dépense ce mois-ci 🎉", { fontSize: 15, color: T.muted }))
    ))
  } else {
    blocks.add(Text("Répartition des dépenses", { fontSize: 14, fontWeight: "bold", color: T.text }))
    cats.forEach(fn(c, i) {
        blocks.add(categoryBar(c, exp))
    })
  }

  return ScrollView({ padding: 16 },
    Column({ spacing: 14, crossAxisAlignment: "start" }, blocks)
  )
}

fn monthHeader(p, inc, exp) {
  let bal = inc - exp
  return Box({ color: T.primary, borderRadius: 16, padding: 18 },
    Column({ crossAxisAlignment: "start", spacing: 12 }, [
        Row({ crossAxisAlignment: "center" }, [
            IconButton("chevron_left", { color: T.onPrimary, onTap: "prevMonth" }),
            Expanded({ flex: 1 },
              Center(Text(monthName(p.m) + " " + intDigits(p.y), { fontSize: 15, fontWeight: "600", color: T.onPrimary }))
            ),
            IconButton("chevron_right", { color: T.onPrimary, onTap: "nextMonth" })
        ]),
        Row({ spacing: 12 }, [
            Expanded({ flex: 1 }, statPill("Revenus", money(inc), T.income)),
            Expanded({ flex: 1 }, statPill("Dépenses", money(exp), T.expense))
        ]),
        statWide("Épargne nette", money(bal))
    ])
  )
}

fn statPill(label, value, accent) {
  return Box({ color: alpha(T.onPrimary, "1F"), borderRadius: 12, padding: 12 },
    Column({ crossAxisAlignment: "start", spacing: 4 }, [
        Row({ spacing: 6, crossAxisAlignment: "center" }, [
            dot(accent, 8),
            Text(label, { fontSize: 12, color: alpha(T.onPrimary, "CC") })
        ]),
        Text(value, { fontSize: 16, fontWeight: "bold", color: T.onPrimary })
    ])
  )
}

fn statWide(label, value) {
  return Box({ color: alpha(T.onPrimary, "1F"), borderRadius: 12, padding: 12 },
    Row({ mainAxisAlignment: "spaceBetween", crossAxisAlignment: "center" }, [
        Text(label, { fontSize: 13, color: alpha(T.onPrimary, "CC") }),
        Text(value, { fontSize: 16, fontWeight: "bold", color: T.onPrimary })
    ])
  )
}

fn categoryBar(c, totalExp) {
  let pct = pctInt(c.total, totalExp)
  return Box({ color: T.surface, borderRadius: 14, padding: 14, borderColor: T.line, borderWidth: 1 },
    Column({ spacing: 10, crossAxisAlignment: "start" }, [
        Row({ crossAxisAlignment: "center", spacing: 10 }, [
            catAvatar(c, 34),
            Expanded({ flex: 1 }, Text(c.label, { fontSize: 14, fontWeight: "600", color: T.text })),
            Text(money(c.total), { fontSize: 14, fontWeight: "bold", color: T.text })
        ]),
        Row({ crossAxisAlignment: "center", spacing: 10 }, [
            Expanded({ flex: 1 }, progressBar(pct, alpha(T.muted, "26"), c.color, 10)),
            Text(intDigits(pct) + "%", { fontSize: 12, fontWeight: "600", color: T.muted })
        ])
    ])
  )
}

// Tri décroissant par `total` (sélection — N petit, pas de comparateur natif).
fn sortByTotalDesc(arr) {
  let items = []
  arr.forEach(fn(c, i) { items.add(c) })
  let out = []
  while (items.length > 0) {
    let bestIdx = 0
    let best = items[0]
    let i = 1
    while (i < items.length) {
      if (items[i].total > best.total) {
        best = items[i]
        bestIdx = i
      }
      i = i + 1
    }
    out.add(best)
    let rest = []
    let j = 0
    while (j < items.length) {
      if (j != bestIdx) { rest.add(items[j]) }
      j = j + 1
    }
    items = rest
  }
  return out
}
