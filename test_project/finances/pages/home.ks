// ============================================================
// Accueil — solde, navigation par mois, budget, recherche,
// filtre par catégorie et liste des transactions par onglet.
// ============================================================
@use "../utils/ui.ks"
@use "../utils/store.ks"

let tx = List([])
let monthOffset = Obs(0)    // 0 = mois courant, -1 = précédent, …
let query = Obs("")         // recherche texte
let catFilter = Obs("all")  // filtre catégorie ("all" = toutes)
let uiTick = Obs(0)         // déclencheur de rebuild (budget)
let budgetDraft = ""        // brouillon du champ budget (modal)

fn refresh() {
  let loaded = loadTx()
  tx.clear()
  tx.addAll(loaded)
}

// Recharge à l'ouverture et à chaque retour sur la page.
fn onInit() { refresh() }
fn onShow() { refresh() }

// --- Période (mois sélectionné) ------------------------------
fn periodMY() {
  return addMonths(month(), year(), monthOffset.value)
}

// --- Actions -------------------------------------------------
fn goAdd() { ui.push("add") }
fn goStats() { ui.push("stats") }
fn onOpen(id) { ui.push("detail", { id: id }) }
fn prevMonth() { monthOffset.set(monthOffset.value - 1) }
fn nextMonth() { monthOffset.set(monthOffset.value + 1) }
fn onSearch(v) { query.set(v) }

fn pickCat(k) {
  if (catFilter.value == k) {
    catFilter.set("all")
  } else {
    catFilter.set(k)
  }
}

// --- Budget (édité via une modale) ---------------------------
fn openBudget() {
  budgetDraft = numToInput(loadBudget())
  ui.showModal("budgetModal")
}
fn onBudgetInput(v) { budgetDraft = v }
fn closeModal() { ui.pop() }

fn saveBudgetVal() {
  let v = toNumber(replace(budgetDraft, ",", "."))
  if (v == null) { v = 0 }
  saveBudget(v)
  uiTick.set(uiTick.value + 1)
  ui.toast("Budget mis à jour")
  ui.pop()
}

fn clearBudget() {
  saveBudget(0)
  uiTick.set(uiTick.value + 1)
  ui.toast("Budget supprimé")
  ui.pop()
}

// --- Filtrage de la liste ------------------------------------
fn matchesQuery(t) {
  let q = query.value
  if (q == "") { return true }
  let ql = toLowerCase(q)
  let cat = categoryByKey(t.category)
  if (contains(toLowerCase(cat.label), ql)) { return true }
  if (contains(toLowerCase(t.note), ql)) { return true }
  return false
}

// Transactions visibles : mois sélectionné + type d'onglet + catégorie
// + recherche, plus récentes d'abord. Lit les Obs pour s'abonner.
fn visibleTx(f) {
  let q = query.value
  let cf = catFilter.value
  let off = monthOffset.value
  let p = periodMY()
  let inMonth = monthItemsFor(tx.value, p.m, p.y)
  let all = reverse(inMonth)
  let out = []
  all.forEach(fn(t, i) {
      let ok = true
      if (f == "income") { if (t.type != "income") { ok = false } }
      if (f == "expense") { if (t.type != "expense") { ok = false } }
      if (cf != "all") { if (t.category != cf) { ok = false } }
      if (ok) { if (matchesQuery(t) == false) { ok = false } }
      if (ok) { out.add(t) }
  })
  return out
}

// --- UI ------------------------------------------------------
fn build() {
  return Scaffold({
      appBar: AppBar({
          backgroundColor: T.primary,
          actions: [ IconButton("info", { onTap: "goStats" }) ]
        },Text("Mes Finances", { color: "white" })),
      backgroundColor: T.bg
    },
    Column({}, [
        Obx({ builder: "header" }),
        searchBar(),
        Obx({ builder: "catFilterRow" }),
        Expanded(
          { flex: 1 },
          TabNav({
              backgroundColor: T.surface,
              labelColor: T.primary,
              unselectedLabelColor: T.muted,
              indicatorColor: T.primary,
              swipeable: true,
              tabs: [
                { label: "Tout",     builder: "listAll" },
                { label: "Revenus",  builder: "listIncome" },
                { label: "Dépenses", builder: "listExpense" }
              ]
          })
        ),
        bottomAdd()
    ])
  )
}

// --- En-tête : mois + solde + budget + flux du mois ----------
fn header() {
  let t = uiTick.value          // rebuild quand le budget change
  let off = monthOffset.value
  let items = tx.value
  let p = periodMY()
  let bal = balance(items)      // solde total (toutes périodes)
  let pItems = monthItemsFor(items, p.m, p.y)
  let inc = sumByType(pItems, "income")
  let exp = sumByType(pItems, "expense")
  return Box({ color: T.primary, padding: { left: 16, right: 16, top: 4, bottom: 12 } },
    Column({ crossAxisAlignment: "start", spacing: 10 }, [
        monthNav(p),
        Column({ crossAxisAlignment: "start", spacing: 1 }, [
            Text("Solde total", { fontSize: 12, color: alpha(T.onPrimary, "B3") }),
            Text(money(bal), { fontSize: 26, fontWeight: "bold", color: T.onPrimary })
        ]),
        budgetBlock(exp),
        Row({ spacing: 10 }, [
            Expanded({ flex: 1 }, flowPill("Revenus", money(inc), T.income)),
            Expanded({ flex: 1 }, flowPill("Dépenses", money(exp), T.expense))
        ])
    ])
  )
}

fn monthNav(p) {
  return Row({ crossAxisAlignment: "center" }, [
      navBtn("chevron_left", "prevMonth"),
      Expanded({ flex: 1 },
        Center(Text(monthName(p.m) + " " + intDigits(p.y), { fontSize: 15, fontWeight: "600", color: T.onPrimary }))
      ),
      navBtn("chevron_right", "nextMonth")
  ])
}

// Bouton chevron compact (l'IconButton natif force une cible tactile de 48px).
fn navBtn(icon, cb) {
  return InkWell({ onTap: cb, borderRadius: 16 },
    Box({ padding: 6, borderRadius: 16 }, Icon(icon, { size: 22, color: T.onPrimary }))
  )
}

fn flowPill(label, value, accent) {
  return Box({ color: alpha(T.onPrimary, "1F"), borderRadius: 12, padding: 10 },
    Column({ crossAxisAlignment: "start", spacing: 2 }, [
        Row({ spacing: 6, crossAxisAlignment: "center" }, [
            dot(accent, 8),
            Text(label, { fontSize: 11, color: alpha(T.onPrimary, "CC") })
        ]),
        Text(value, { fontSize: 15, fontWeight: "bold", color: T.onPrimary })
    ])
  )
}

// Bloc budget : jauge si défini, sinon invite à le définir.
fn budgetBlock(spent) {
  let b = loadBudget()
  if (b <= 0) {
    return InkWell({ onTap: "openBudget", borderRadius: 12 },
      Box({ color: alpha(T.onPrimary, "1F"), borderRadius: 12, padding: 10 },
        Row({ spacing: 8, crossAxisAlignment: "center" }, [
            Icon("add", { size: 18, color: T.onPrimary }),
            Text("Définir un budget mensuel", { fontSize: 13, fontWeight: "600", color: T.onPrimary })
        ])
      )
    )
  }
  let pct = pctInt(spent, b)
  let over = spent > b
  let fillColor = T.onPrimary
  let restLabel = "Reste " + money(b - spent)
  if (over) {
    fillColor = T.warn
    restLabel = "Dépassé de " + money(spent - b)
  }
  return InkWell({ onTap: "openBudget", borderRadius: 12 },
    Box({ color: alpha(T.onPrimary, "1F"), borderRadius: 12, padding: 12 },
      Column({ spacing: 8, crossAxisAlignment: "start" }, [
          Row({ mainAxisAlignment: "spaceBetween", crossAxisAlignment: "center" }, [
              Text("Budget du mois", { fontSize: 12, color: alpha(T.onPrimary, "CC") }),
              Text(money(spent) + " / " + money(b), { fontSize: 12, fontWeight: "600", color: T.onPrimary })
          ]),
          progressBar(pct, alpha(T.onPrimary, "33"), fillColor, 8),
          Text(restLabel, { fontSize: 11, color: alpha(T.onPrimary, "CC") })
      ])
    )
  )
}

// --- Recherche & filtre catégorie ----------------------------
fn searchBar() {
  return Box({ color: T.bg, padding: { left: 12, right: 12, top: 8, bottom: 4 } },
    TextField({
        value: query.value,
        onChange: "onSearch",
        placeholder: "Rechercher (note, catégorie)",
        prefixIcon: "search",
        backgroundColor: T.surface
    })
  )
}

fn catFilterRow() {
  let cf = catFilter.value
  let chips = [ filterChip("Toutes", "all", cf) ]
  CATEGORIES.forEach(fn(c, i) {
      chips.add(filterChip(c.emoji + " " + c.label, c.key, cf))
  })
  return Box({ color: T.bg },
    ScrollView({ direction: "horizontal", padding: { left: 12, right: 12, top: 2, bottom: 8 } },
      Row({ spacing: 8 }, chips)
    )
  )
}

fn filterChip(label, key, current) {
  let bg = T.surface
  let fg = T.muted
  let bd = T.line
  if (key == current) {
    bg = T.primary
    fg = T.onPrimary
    bd = T.primary
  }
  return InkWell({ onTap: "pickCat", arg: key, borderRadius: 20 },
    Box({ color: bg, borderRadius: 20, padding: 8, borderColor: bd, borderWidth: 1 },
      Text(label, { fontSize: 12, fontWeight: "600", color: fg })
    )
  )
}

// --- Onglets : une vue filtrée par onglet, réactive ----------
fn listAll()     { return txList("all") }
fn listIncome()  { return txList("income") }
fn listExpense() { return txList("expense") }

fn txList(f) {
  let items = visibleTx(f)
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
    Box({ color: T.surface, borderRadius: 16, padding: 12, borderColor: T.line, borderWidth: 1 },
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
        Text("Ajoutez-en une ou changez de mois", { fontSize: 13, color: T.muted })
    ])
  )
}

fn bottomAdd() {
  return Box({ color: T.surface, padding: 14 },
    Button("Nouvelle transaction", { onTap: "goAdd", color: T.primary, fullWidth: true, icon: "add" })
  )
}

// --- Modale budget -------------------------------------------
fn budgetModal() {
  return Box({ color: T.surface, borderRadius: 18, padding: 20 },
    Column({ crossAxisAlignment: "start", spacing: 14, mainAxisSize: "min" }, [
        Text("Budget mensuel", { fontSize: 17, fontWeight: "bold", color: T.text }),
        Text("Plafond de dépenses pour le mois.", { fontSize: 13, color: T.muted }),
        TextField({ labelText: "Montant (€)", value: budgetDraft, onChange: "onBudgetInput", keyboardType: "number", prefixIcon: "payment" }),
        Row({ spacing: 10 }, [
            Expanded({ flex: 1 }, Button("Annuler", { onTap: "closeModal", variant: "text", color: T.muted, fullWidth: true })),
            Expanded({ flex: 1 }, Button("Enregistrer", { onTap: "saveBudgetVal", color: T.primary, fullWidth: true }))
        ]),
        clearBudgetBtn()
    ])
  )
}

fn clearBudgetBtn() {
  if (loadBudget() <= 0) { return Box({}) }
  return Button("Supprimer le budget", { onTap: "clearBudget", variant: "text", color: T.danger, fullWidth: true })
}
