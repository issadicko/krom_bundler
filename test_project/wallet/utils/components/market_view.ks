// ============================================================
// Onglet Marketplace : enchaînement d'écrans dans l'onglet (sans logique
// métier). Liste filtrable par catégorie -> détail d'une offre -> activation
// (état visuel). La vue courante est pilotée par `marketView` (Obs).
// ============================================================
@use "../ui.ks"
@use "../data.ks"
@use "../state.ks"
@use "./shared.ks"

// L'onglet rend une vue réactive : liste ou détail.
fn shopTab() {
  return Obx({ builder: "marketBody" })
}

fn marketBody() {
  let view = marketView.value
  if (view == "detail") {
    return marketDetail()
  }
  return marketList()
}

// --- Navigation (UI only) ------------------------------------
fn openOffer(o) {
  selectedOffer = o
  activated.set(false)
  marketView.set("detail")
}
fn backToMarket() { marketView.set("list") }
fn activateOffer() {
  activated.set(true)
  ui.toast("Offre activée")
}
fn pickMarketCat(k) {
  if (marketCat.value == k) {
    marketCat.set("all")
  } else {
    marketCat.set(k)
  }
}

// --- Écran liste ---------------------------------------------
fn marketList() {
  return tabScreen("Marketplace", [
      marketCatRow(),
      featuredOffer(),
      offerGrid()
  ])
}

fn marketCatRow() {
  let cur = marketCat.value
  let chips = [ marketChip("Toutes", "all", cur) ]
  OFFER_CATS.forEach(fn(c, i) { chips.add(marketChip(c.label, c.key, cur)) })
  return ScrollView({ direction: "horizontal" },
    Row({ spacing: 8 }, chips)
  )
}

fn marketChip(label, key, cur) {
  let bg = T.card
  let fg = T.muted
  if (key == cur) {
    bg = T.ink
    fg = T.onInk
  }
  return InkWell({ onTap: "pickMarketCat", arg: key, borderRadius: 18 },
    Box({ color: bg, borderRadius: 18, padding: { left: 14, right: 14, top: 8, bottom: 8 } },
      Text(label, { fontSize: 13, fontWeight: "600", color: fg })
    )
  )
}

fn featuredOffer() {
  let o = OFFERS[0]
  return InkWell({ onTap: "openOffer", arg: o, borderRadius: 22 },
    Box({ gradient: { colors: ["#F0ABFC", "#D946EF"], angle: 135 }, borderRadius: 22, padding: 20 },
      Column({ crossAxisAlignment: "start", spacing: 6 }, [
          Text("À la une", { fontSize: 12, fontWeight: "600", color: alpha("#FFFFFF", "CC") }),
          Text(o.brand + " · " + o.perk, { fontSize: 18, fontWeight: "bold", color: "#FFFFFF" }),
          Text("Touchez pour découvrir l'offre", { fontSize: 13, color: alpha("#FFFFFF", "D9") })
      ])
    )
  )
}

fn offerGrid() {
  let cur = marketCat.value
  let items = []
  OFFERS.forEach(fn(o, i) {
      if (cur == "all") {
        items.add(o)
      } else {
        if (o.cat == cur) { items.add(o) }
      }
  })
  if (items.length == 0) {
    return Box({ padding: 24 }, Center(Text("Aucune offre dans cette catégorie", { fontSize: 14, color: T.muted })))
  }
  let rows = []
  let i = 0
  let n = items.length
  while (i < n) {
    let cells = [ Expanded({ flex: 1 }, offerCard(items[i])) ]
    if (i + 1 < n) {
      cells.add(Expanded({ flex: 1 }, offerCard(items[i + 1])))
    } else {
      cells.add(Expanded({ flex: 1 }, Box({})))
    }
    // crossAxisAlignment must NOT be "stretch" here: a Row's cross axis is
    // vertical, and this Row lives inside a vertical ScrollView (unbounded
    // height) — stretch would force an infinite height and crash layout.
    rows.add(Row({ spacing: 12, crossAxisAlignment: "start" }, cells))
    i = i + 2
  }
  return Column({ spacing: 12 }, rows)
}

fn offerCard(o) {
  return InkWell({ onTap: "openOffer", arg: o, borderRadius: 20 },
    Box({ color: T.card, borderRadius: 20, padding: 16 },
      Column({ crossAxisAlignment: "start", spacing: 10 }, [
          avatarCircle(o.emoji, o.color, 40),
          Text(o.brand, { fontSize: 14, fontWeight: "600", color: T.text }),
          Box({ color: alpha(T.income, "1F"), borderRadius: 12, padding: { left: 8, right: 8, top: 4, bottom: 4 } },
            Text(o.perk, { fontSize: 12, fontWeight: "600", color: T.income })
          )
      ])
    )
  )
}

// --- Écran détail --------------------------------------------
fn marketDetail() {
  let o = selectedOffer
  if (o == null) {
    return tabScreen("Offre", [ Text("—", { color: T.muted }) ])
  }
  return ScrollView({ padding: { left: 16, right: 16, top: 16, bottom: 110 } },
    Column({ crossAxisAlignment: "stretch", spacing: 16 }, [
        Row({ crossAxisAlignment: "center", spacing: 12 }, [
            InkWell({ onTap: "backToMarket", borderRadius: 20 },
              Box({ width: 40, height: 40, borderRadius: 20, color: T.card },
                Center(Icon("arrow_back", { size: 20, color: T.text }))
              )
            ),
            Text("Offre", { fontSize: 20, fontWeight: "bold", color: T.text })
        ]),
        Box({ color: T.card, borderRadius: 22, padding: 20 },
          Column({ crossAxisAlignment: "center", spacing: 10 }, [
              avatarCircle(o.emoji, o.color, 64),
              Text(o.brand, { fontSize: 20, fontWeight: "bold", color: T.text }),
              Box({ color: alpha(T.income, "1F"), borderRadius: 14, padding: { left: 12, right: 12, top: 6, bottom: 6 } },
                Text(o.perk, { fontSize: 14, fontWeight: "600", color: T.income })
              )
          ])
        ),
        listCard(Column({ crossAxisAlignment: "start", spacing: 8 }, [
              Text("Description", { fontSize: 14, fontWeight: "bold", color: T.text }),
              Text(o.desc, { fontSize: 14, color: T.muted })
        ])),
        listCard(Column({ crossAxisAlignment: "start", spacing: 12 }, [
              Text("Comment ça marche", { fontSize: 14, fontWeight: "bold", color: T.text }),
              howStep("1", "Activez l'offre ci-dessous"),
              howStep("2", "Payez avec votre carte Wallet"),
              howStep("3", "Le cashback est crédité sous 48h")
        ])),
        Obx({ builder: "activateButton" })
    ])
  )
}

fn howStep(n, label) {
  return Row({ crossAxisAlignment: "center", spacing: 12 }, [
      Box({ width: 26, height: 26, borderRadius: 13, color: T.ink },
        Center(Text(n, { fontSize: 13, fontWeight: "bold", color: T.onInk }))
      ),
      Expanded({ flex: 1 }, Text(label, { fontSize: 14, color: T.text }))
  ])
}

fn activateButton() {
  let on = activated.value
  if (on) {
    return Box({ color: alpha(T.income, "1F"), borderRadius: 16, padding: 16 },
      Row({ mainAxisAlignment: "center", crossAxisAlignment: "center", spacing: 8 }, [
          Icon("check", { size: 20, color: T.income }),
          Text("Offre activée", { fontSize: 15, fontWeight: "600", color: T.income })
      ])
    )
  }
  return Button("Activer l'offre", { onTap: "activateOffer", color: T.ink, fullWidth: true })
}
