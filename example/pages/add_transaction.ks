@use "../store/finance_store"

let title = Obs("")
let amount = Obs("")
let isExpense = Obs(true)

fn build() {
  return Scaffold({
    appBar: AppBar({ title: "Nouvelle Transaction", backgroundColor: Theme.primary }),
    body: Column({ padding: 16, spacing: 20 }, [
      
      // Type Selector (Income / Expense)
      Obx({ builder: "typeSelector" }),
      
      // Title Input
      TextField({
        labelText: "Titre",
        placeholder: "Ex: Courses, Loyer...",
        onChange: "setTitle"
      }),
      
      // Amount Input
      TextField({
        labelText: "Montant (€)",
        keyboardType: "number",
        onChange: "setAmount"
      }),
      
      // Save Button
      Button("Enregistrer", {
        onTap: "saveTransaction",
        fullWidth: true,
        size: "large",
        color: Theme.primary,
        icon: "check"
      })
    ])
  })
}

fn typeSelector() {
  let expenseColor = "grey"
  if (isExpense.value) {
    expenseColor = Theme.danger
  }
  
  let incomeColor = "grey"
  if (!isExpense.value) {
    incomeColor = Theme.success
  }

  return Row({ spacing: 10 }, [
    Button("Dépense", {
      color: expenseColor,
      onTap: "setExpense",
      flex: 1
    }),
    Button("Revenu", {
      color: incomeColor,
      onTap: "setIncome",
      flex: 1
    })
  ])
}

fn setExpense() { isExpense.set(true) }
fn setIncome() { isExpense.set(false) }
fn setTitle(val) { title.set(val) }
fn setAmount(val) {
  amount.set(val)
 }

fn saveTransaction() {
  if (title.value == "" || amount.value == "") {
    // Show error or just return
    ui.toast("Veuillez remplir tous les champs")
    return
  }
  
  // Call store function
  addTransaction(title.value, amount.value, isExpense.value)
  
  // Go back
  ui.pop()
}
