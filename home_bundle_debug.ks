// ===== formatters.ks =====
// Fonctions de formatage
fn formatMoney(amount) {
  if (amount >= 0) {
    return "+" + amount + " €"
  }
  return amount + " €"
}

fn formatDate(date) {
  return date
}


// ===== colors.ks =====
// Palette de couleurs
let colors = {
  primary: "#3B82F6",
  success: "#22C55E",
  danger: "#EF4444",
  warning: "#F59E0B",
  purple: "#8B5CF6",
  pink: "#EC4899"
}

fn getTransactionColor(type) {
  if (type == "income") {
    return colors.success
  }
  return colors.danger
}


// ===== home.ks =====
// === quick_action.ks ===
fn QuickAction(iconName, label, bgColor, onTap) {
  return Box({ borderRadius: 16, width: 85, height: 85, color: "white" }, 
    InkWell({ onTap: onTap, borderRadius: 12 }, 
      Column({ spacing: 8, mainAxisAlignment: "center" }, [
        Box({ width: 42, height: 42, color: bgColor, borderRadius: 16, alignment: "center" }, 
          Icon(iconName, { size: 20, color: "white" })
        ),
        Text(label, { fontSize: 14, color: "black" })
      ])
    )
  )
}


// === transaction_card.ks ===
// Composant TransactionCard réutilisable
fn TransactionCard(tx) {
  let iconName = "arrow_forward"
  if (tx.type != "income") {
    iconName = "arrow_back"
  }
  
  return Box({ padding: 16, borderRadius: 12, color: "white", borderColor: "#E0E0E0" }, 
    Row({ crossAxisAlignment: "center", spacing: 12 }, [
      Box({ width: 44, height: 44, borderRadius: 22, color: getTransactionColor(tx.type) + "20" }, 
        Box({ alignment: "center" }, 
          Icon(iconName, { size: 20, color: getTransactionColor(tx.type) })
        )
      ),
      Expanded({}, 
        Column({ crossAxisAlignment: "start", spacing: 4 }, [
          Text(tx.title, { fontSize: 16, fontWeight: "bold", color: "black" }),
          Text(tx.date, { fontSize: 12, color: "grey" })
        ])
      ),
      Text(formatMoney(tx.amount), { fontSize: 16, fontWeight: "bold", color: getTransactionColor(tx.type) })
    ])
  )
}


// === colors.ks ===
// Palette de couleurs
let colors = {
  primary: "#3B82F6",
  success: "#22C55E",
  danger: "#EF4444",
  warning: "#F59E0B",
  purple: "#8B5CF6",
  pink: "#EC4899"
}

fn getTransactionColor(type) {
  if (type == "income") {
    return colors.success
  }
  return colors.danger
}


// === home.ks ===
let balance = Obs(15420)
let transactions = [
  { type: "income", title: "Salaire", amount: 3200, date: "25 Jan" },
  { type: "expense", title: "Loyer", amount: -850, date: "24 Jan" },
  { type: "expense", title: "Courses", amount: -127.30, date: "23 Jan" }
]

fn build() {
  return Scaffold({ backgroundColor: "#fefcf3" }, 
    Box({ color: "#fefcf3", height: "infinity", width: "infinity" }, 
      ScrollView({ padding: 16, direction: "vertical" }, 
        Column({ spacing: 16 }, [
          // Header
          Row({ mainAxisAlignment: "spaceBetween", crossAxisAlignment: "center" }, [
            Column({ crossAxisAlignment: "start", spacing: 4 }, [
              Text("Bonjour, Issa 👋", { fontSize: 14, color: "grey" }),
              Text("Tableau de bord", { fontSize: 24, fontWeight: "bold", color: "black" })
            ]),
            Row({ spacing: 12 }, [
              IconButton("refresh", { size: 24, color: "black", onTap: "onRefresh" }),
              Box({ width: 48, height: 48, borderRadius: 24, color: "black" }, 
                Icon("person", { size: 24, color: "white" })
              )
            ])
          ]),
          
          // Balance Card
          Box({ width: "infinity", padding: 24, borderRadius: 16, color: "black" }, 
            Column({ spacing: 8 }, [
              Text("Solde total", { fontSize: 14, color: "white" }),
              Obx({ builder: "balanceBuilder" })
            ])
          ),
          
          ScrollView({ direction: "horizontal", padding: 0.1 }, 
            Row({ spacing: 16 }, [
              QuickAction("cart", "Achats", colors.purple, "onShop"),
              QuickAction("home", "Maison", colors.warning, "onHome"),
              QuickAction("favorite", "Épargne", colors.pink, "onSave"),
              QuickAction("star", "Objectifs", colors.success, "onGoals"),
              QuickAction("swap_horiz", "Transfert", colors.primary, "onTransfer")
            ])
          ]),
          
          // Transactions
          Text("Transactions récentes", { fontSize: 18, fontWeight: "bold", color: "black" }),
          Obx({ builder: "transactionsBuilder" })
        ])
      )
    )
  )
}

fn balanceBuilder() {
  return Text(balance.value + " €", { fontSize: 32, fontWeight: "bold", color: "white" })
}

fn transactionsBuilder() {
  // Workaround for compiler scope issue: defined locally
  let txs = [
    { type: "income", title: "Salaire", amount: 3200, date: "25 Jan" },
    { type: "expense", title: "Loyer", amount: -850, date: "24 Jan" },
    { type: "expense", title: "Courses", amount: -127.30, date: "23 Jan" }
  ]
  return Column({ spacing: 12 }, map(txs, buildTransactionItem))
}

fn buildTransactionItem(tx) {
  return TransactionCard(tx)
}

fn onShop() { ui.toast("Achats") }
fn onHome() { ui.toast("Maison") }
fn onSave() { ui.toast("Épargne") }
fn onGoals() { ui.toast("Objectifs") }
fn onTransfer() { ui.push("transfer") }

fn onRefresh() {
  ui.showProgress({ message: "Actualisation..." })
  balance.value = balance.value + (rand() * 100).toInt()
  ui.toast("Données actualisées")
  ui.hideProgress()
}



