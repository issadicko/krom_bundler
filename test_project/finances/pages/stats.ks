// ============================================================
// Statistiques — bilan du mois + répartition des dépenses par
// catégorie (barres proportionnelles via le flex des Expanded).
// ============================================================
@use "../utils/ui.ks"
@use "../utils/store.ks"

let tick = Obs(0)

fn onInit() { tick.set(tick.value + 1) }
fn onShow() { tick.set(tick.value + 1) }
fn back() { ui.pop() }

fn build() {
  return Scaffold({
      appBar: AppBar({ title: "Statistiques du mois", backgroundColor: T.primary }),
      backgroundColor: T.bg
    },
    Obx({ builder: "content" })
  )
}

fn content() {
  let v = tick.value
  let items = monthItems(loadTx())
  let inc = sumByType(items, "income")
  let exp = sumByType(items, "expense")
  let cats = sortByTotalDesc(expenseByCategory(items))

  let blocks = [ monthHeader(inc, exp) ]

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

fn monthHeader(inc, exp) {
  let bal = inc - exp
  return Card({ borderRadius: 16, padding: 18, color: T.primary },
    Column({ crossAxisAlignment: "start", spacing: 12 }, [
        Text("Bilan du mois", { fontSize: 13, color: "#DBEAFE" }),
        Row({ spacing: 12 }, [
            Expanded({ flex: 1 }, statBox("Revenus", money(inc), T.incomeBg, T.income)),
            Expanded({ flex: 1 }, statBox("Dépenses", money(exp), T.expenseBg, T.expense))
        ]),
        statBox("Épargne nette", money(bal), T.chipBg, T.primaryDark)
    ])
  )
}

fn statBox(label, value, bg, fg) {
  return Box({ color: bg, borderRadius: 12, padding: 12 },
    Column({ crossAxisAlignment: "start", spacing: 4 }, [
        Text(label, { fontSize: 12, color: fg }),
        Text(value, { fontSize: 16, fontWeight: "bold", color: fg })
    ])
  )
}

fn categoryBar(c, totalExp) {
  let pct = 0
  if (totalExp > 0) { pct = floor(c.total * 100 / totalExp) }

  let fillFlex = pct
  if (fillFlex < 1) { fillFlex = 1 }
  let restFlex = 100 - pct
  if (restFlex < 1) { restFlex = 1 }

  return Box({ color: T.surface, borderRadius: 14, padding: 14 },
    Column({ spacing: 10, crossAxisAlignment: "start" }, [
        Row({ crossAxisAlignment: "center", spacing: 10 }, [
            catAvatar(c, 34),
            Expanded({ flex: 1 }, Text(c.label, { fontSize: 14, fontWeight: "600", color: T.text })),
            Text(money(c.total), { fontSize: 14, fontWeight: "bold", color: T.text })
        ]),
        Row({ crossAxisAlignment: "center", spacing: 10 }, [
            Expanded({ flex: 1 },
              Box({ color: T.bg, borderRadius: 6 },
                Row({}, [
                    Expanded({ flex: fillFlex }, Box({ color: c.color, borderRadius: 6, height: 10 })),
                    Expanded({ flex: restFlex }, Box({ height: 10 }))
                ])
              )
            ),
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
