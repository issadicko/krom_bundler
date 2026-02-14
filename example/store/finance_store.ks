let transactions = List([])
let balance = Obs(0.0)
let income = Obs(0.0)
let expense = Obs(0.0)

fn addTransaction(title, amount, isExpense) {
  let t = {
    "id": now(),
    "title": title,
    "amount": toDouble(amount),
    "isExpense": isExpense,
    "date": now()
  }
  transactions.add(t)
  calculateBalance()
}

fn removeTransaction(index) {
  transactions.removeAt(index)
  calculateBalance()
}

fn calculateBalance() {
  let total = 0.0
  let inc = 0.0
  let exp = 0.0
  
  transactions.forEach(fn(t) {
    if (t.isExpense) {
      total = total - t.amount
      exp = exp + t.amount
    } else {
      total = total + t.amount
      inc = inc + t.amount
    }
  })
  
  balance.set(total)
  income.set(inc)
  expense.set(exp)
}

// Initial dummy data
addTransaction("Salaire", 2500, false)
addTransaction("Loyer", 800, true)
addTransaction("Courses", 150.50, true)
