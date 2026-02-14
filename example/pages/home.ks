@use "../store/finance_store"
@use "../utils/formatters"

fn build() {
  return Scaffold({
    appBar: AppBar({ 
      title: "Finance Perso", 
      backgroundColor: Theme.primary,
      actions: [
        IconButton("refresh", { onTap: "onRefresh" }),
        IconButton("bar_chart", { onTap: "goToStats" })
      ]
    }),
    body: RefreshIndicator({ onRefresh: "onRefresh" },
      ScrollView({ padding: 16 },
        Column({ spacing: 16 }, [
          // Balance Card with enhanced design 💰
          Card({ elevation: 8, borderRadius: 20, padding: 28, color: Theme.primary }, 
            Column({ spacing: 16, crossAxisAlignment: "center" }, [
              Row({ mainAxisAlignment: "spaceBetween", crossAxisAlignment: "center" }, [
                Column({ crossAxisAlignment: "start" }, [
                  Text("💳 Mon Solde Total", { color: "white", fontSize: 16, opacity: 0.9 }),
                  Obx({ builder: "balanceDisplay" })
                ]),
                Icon("savings", { size: 36, color: "white", opacity: 0.9 })
              ]),
              Divider({ color: "white", opacity: 0.3 }),
              Row({ mainAxisAlignment: "spaceEvenly" }, [
                Column({ crossAxisAlignment: "center", spacing: 4 }, [
                  Obx({ builder: "incomeDisplay" }),
                  Text("Revenus", { color: "white", fontSize: 12, opacity: 0.8 })
                ]),
                
                Column({ crossAxisAlignment: "center", spacing: 4 }, [
                  Obx({ builder: "expenseDisplay" }),
                  Text("Dépenses", { color: "white", fontSize: 12, opacity: 0.8 })
                ])
              ])
            ])
          ),
          
          // Quick Actions Grid 🚀
          Card({ elevation: 4, borderRadius: 16, padding: 20 },
            Column({ spacing: 16 }, [
              Text("🎯 Actions Rapides", { fontSize: 18, fontWeight: "bold", color: Theme.text }),
              Grid({ columns: 2, spacing: 16 }, [
                InkWell({ onTap: "goToAdd", borderRadius: 12 },
                  Card({ elevation: 3, padding: 20, color: Theme.secondary },
                    Column({ crossAxisAlignment: "center", spacing: 10 }, [
                      Icon("add_circle", { size: 28, color: "white" }),
                      Text("➕ Ajouter", { color: "white", fontSize: 15, fontWeight: "bold" })
                    ])
                  )
                ),
                InkWell({ onTap: "goToStats", borderRadius: 12 },
                  Card({ elevation: 3, padding: 20, color: Theme.primary },
                    Column({ crossAxisAlignment: "center", spacing: 10 }, [
                      Icon("bar_chart", { size: 28, color: "white" }),
                      Text("📊 Stats", { color: "white", fontSize: 15, fontWeight: "bold" })
                    ])
                  )
                )
              ])
            ])
          ),
          
          // Transactions Section
          Card({ elevation: 2, borderRadius: 12, padding: 16 },
            Column({ spacing: 12 }, [
              Row({ mainAxisAlignment: "spaceBetween", crossAxisAlignment: "center" }, [
                Text("Transactions Récentes", { fontSize: 16, fontWeight: "bold", color: Theme.text }),
                InkWell({ onTap: "goToTransactions" },
                  Text("Voir tout", { color: Theme.primary, fontSize: 14 })
                )
              ]),
              Obx({ builder: "transactionList" })
            ])
          )
        ])
      )
    )
  })
}

fn balanceDisplay() {
  return Text(balance.value + " €", { color: "white", fontSize: 32, fontWeight: "bold" })
}

fn incomeDisplay() {
  return Text("+" + income.value + " €", { color: "white", fontSize: 18, fontWeight: "bold" })
}

fn expenseDisplay() {
  return Text("-" + expense.value + " €", { color: "white", fontSize: 18, fontWeight: "bold" })
}

fn transactionList() {
  if (transactions.value.length == 0) {
    return Center(
      Column({ spacing: 8, crossAxisAlignment: "center" }, [
        Icon("receipt_long", { size: 48, color: "grey", opacity: 0.5 }),
        Text("Aucune transaction", { color: "grey", fontSize: 16 })
      ])
    )
  }

  return Column({ spacing: 8 }, 
    transactions.value.map(fn(t) {
      let iconName = "arrow_upward"
      let bgColor = Theme.success + "20"
      let textColor = Theme.success
      let prefix = "+"
      
      if (t.isExpense) {
        iconName = "arrow_downward"
        bgColor = Theme.danger + "20"
        textColor = Theme.danger
        prefix = "-"
      }

      return ListTile({
        leading: Box({ width: 40, height: 40, borderRadius: 20, color: bgColor, alignment: "center" },
          Icon(iconName, { size: 20, color: textColor })
        ),
        title: Text(t.title, { fontWeight: "bold", fontSize: 16 }),
        subtitle: Text(formatDate(t.date), { color: "grey", fontSize: 12 }),
        trailing: Text(prefix + t.amount + " €", { 
          color: textColor, 
          fontWeight: "bold", 
          fontSize: 16 
        }),
        onTap: "onTransactionTap"
      })
    })
  )
}

fn onRefresh() {
  ui.toast("Actualisation des données...")
  calculateBalance()
  delayed(1000, fn() {
    ui.toast("Données actualisées !")
  })
}

fn goToAdd() { ui.push("add_transaction") }
fn goToStats() { ui.push("stats") }
fn goToTransactions() { ui.push("transactions") }
fn onTransactionTap() { ui.toast("Détails de la transaction") }
