// ============================================================
// Onglet Home : en-tête, carrousel de soldes, actions, opérations,
// bannière dégradée.
// ============================================================
@use "../ui.ks"
@use "../data.ks"
@use "../state.ks"
@use "./shared.ks"

fn homeTab() {
  return ScrollView({ padding: { left: 16, right: 16, top: 14, bottom: 110 } },
    Column({ spacing: 20 }, [
        topBar(),
        balanceBlock(),
        quickActions(),
        Obx({ builder: "operationsCard" }),
        promoBanner()
    ])
  )
}

fn topBar() {
  return Row({ crossAxisAlignment: "center", spacing: 12 }, [
      avatarCircle("🧑", "#6366F1", 44),
      Expanded({ flex: 1 }, searchPill()),
      roundBtn("sort", "noop"),
      roundBtn("payment", "noop"),
      // Réserve le coin haut-droit pour la capsule "•••" de l'hôte.
      SizedBox({ width: 30 })
  ])
}

fn searchPill() {
  return Box({ color: T.card, borderRadius: 24, padding: { left: 16, right: 16, top: 13, bottom: 13 } },
    Row({ spacing: 10, crossAxisAlignment: "center" }, [
        Icon("search", { size: 18, color: T.muted }),
        Text("Search", { fontSize: 15, color: T.muted })
    ])
  )
}

fn roundBtn(icon, cb) {
  return InkWell({ onTap: cb, borderRadius: 23 },
    Box({ width: 46, height: 46, borderRadius: 23, color: T.card },
      Center(Icon(icon, { size: 20, color: T.text }))
    )
  )
}

// Carrousel de comptes (PageView swipeable, aperçu des voisines via
// viewportFraction) + points synchronisés.
fn balanceBlock() {
  return Column({ crossAxisAlignment: "center", spacing: 8 }, [
      PageView({
          height: 116,
          viewportFraction: 0.86,
          onChange: "onAccountChange",
          pages: [ { builder: "acct0" }, { builder: "acct1" }, { builder: "acct2" } ]
      }),
      Obx({ builder: "managePill" })
  ])
}

fn onAccountChange(i) { currentAccount.set(i) }

fn acct0() { let v = tick.value  return accountCard(ACCOUNTS[0]) }
fn acct1() { let v = tick.value  return accountCard(ACCOUNTS[1]) }
fn acct2() { let v = tick.value  return accountCard(ACCOUNTS[2]) }

fn accountCard(a) {
  return Box({ margin: { left: 6, right: 6 }, borderRadius: 22, padding: { left: 18, right: 18, top: 16, bottom: 16 }, color: "#FFFFFF" },
    Column({ crossAxisAlignment: "center", mainAxisAlignment: "center", spacing: 4 }, [
        Text(a.label, { fontSize: 14, fontWeight: "600", color: T.muted }),
        Text(fmtMoney(a.balance, a.sym), { fontSize: 34, fontWeight: "bold", color: T.text })
    ])
  )
}

fn managePill() {
  let idx = currentAccount.value
  let dots = []
  let i = 0
  while (i < ACCOUNTS.length) {
    dots.add(navDot(i == idx))
    i = i + 1
  }
  return Box({ color: T.card, borderRadius: 20, padding: { left: 14, right: 14, top: 7, bottom: 7 } },
    Row({ spacing: 10, crossAxisAlignment: "center", mainAxisSize: "min" }, [
        Row({ spacing: 5, crossAxisAlignment: "center" }, dots),
        Box({ width: 1, height: 14, color: T.line }),
        Row({ spacing: 2, crossAxisAlignment: "center" }, [
            Text("Manage", { fontSize: 13, fontWeight: "600", color: T.text }),
            Icon("chevron_right", { size: 16, color: T.muted })
        ])
    ])
  )
}

fn navDot(active) {
  let c = T.line
  if (active) { c = T.text }
  return Box({ width: 6, height: 6, borderRadius: 6, color: c })
}

fn quickActions() {
  return Row({ mainAxisAlignment: "center", crossAxisAlignment: "center", spacing: 10 }, [
      quickAction("add", "Top up", "noop"),
      quickAction("send", "Move", "noop"),
      quickAction("receipt", "Details", "noop"),
      quickAction("more_horiz", "More", "noop")
  ])
}

fn quickAction(icon, label, cb) {
  return InkWell({ onTap: cb, borderRadius: 16 },
    Column({ crossAxisAlignment: "center", spacing: 8 }, [
        Box({ width: 58, height: 58, borderRadius: 29, color: T.ink },
          Center(Icon(icon, { size: 24, color: T.onInk }))
        ),
        Text(label, { fontSize: 12, color: T.text })
    ])
  )
}

fn operationsCard() {
  let v = tick.value
  let list = reverse(TX)
  let rows = []
  let i = 0
  while (i < list.length) {
    if (i < 4) { rows.add(opRow(list[i])) }
    i = i + 1
  }
  return Box({ color: T.card, borderRadius: 24, padding: 16 },
    Column({ spacing: 14 }, [
        Row({ mainAxisAlignment: "spaceBetween", crossAxisAlignment: "center" }, [
            Text("Operations", { fontSize: 17, fontWeight: "bold", color: T.text }),
            chip("All")
        ]),
        Column({ spacing: 14 }, rows)
    ])
  )
}

fn promoBanner() {
  return Box({ gradient: { colors: ["#F0ABFC", "#D946EF"], angle: 135 }, borderRadius: 24, padding: 20 },
    Column({ crossAxisAlignment: "start", spacing: 6 }, [
        Text("Earn 4.2% on idle USD", { fontSize: 18, fontWeight: "bold", color: "#FFFFFF" }),
        Text("Open a Savings Vault in under a minute.", { fontSize: 13, color: alpha("#FFFFFF", "D9") }),
        SizedBox({ height: 10 }),
        InkWell({ onTap: "noop", borderRadius: 22 },
          Box({ color: T.ink, borderRadius: 22, padding: { left: 18, right: 18, top: 12, bottom: 12 } },
            Text("Open vault", { fontSize: 14, fontWeight: "600", color: T.onInk })
          )
        )
    ])
  )
}
