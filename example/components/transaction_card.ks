// Composant TransactionCard reutilisable
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
