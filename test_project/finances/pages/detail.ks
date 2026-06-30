// ============================================================
// Détail d'une transaction (modifier / supprimer). `args.id` vient de
// ui.push. Obs(null) étant piégeux en KromScript, on garde l'id en variable
// et on utilise `tick` (Obs entier) comme simple déclencheur de rebuild.
// ============================================================
@use "../utils/ui.ks"
@use "../utils/store.ks"

let txId = ""
let tick = Obs(0)

fn refresh() {
  if (args != null) { txId = args.id }
  tick.set(tick.value + 1)
}

fn onInit() { refresh() }
fn onShow() { refresh() }
fn back() { ui.pop() }

fn edit() {
  if (txId == "") { return }
  ui.push("add", { id: txId })
}

fn remove() {
  if (txId == "") { return }
  deleteTxById(txId)
  ui.toast("Transaction supprimée")
  ui.pop()
}

fn build() {
  return Scaffold({
      appBar: AppBar({ title: "Détail", backgroundColor: T.primary }),
      backgroundColor: T.bg
    },
    Obx({ builder: "content" })
  )
}

fn content() {
  let v = tick.value          // abonne l'Obx au déclencheur
  let t = txById(txId)        // map ou null (variable locale)
  if (t == null) {
    return Center(Text("Transaction introuvable", { fontSize: 16, color: T.muted }))
  }

  let cat = categoryByKey(t.category)
  let amountColor = T.expense
  let typeLabel = "Dépense"
  if (t.type == "income") {
    amountColor = T.income
    typeLabel = "Revenu"
  }

  let noteText = t.note
  if (noteText == "") { noteText = "—" }

  return ScrollView({ padding: 16 },
    Column({ spacing: 16, crossAxisAlignment: "start" }, [
        Card({ borderRadius: 16, padding: 20, color: T.surface },
          Column({ spacing: 12, crossAxisAlignment: "center", mainAxisAlignment: "center" }, [
              catAvatar(cat, 64),
              Text(signedMoney(t.amount, t.type), { fontSize: 30, fontWeight: "bold", color: amountColor }),
              Box({ color: alpha(amountColor, "1F"), borderRadius: 20, padding: 8 },
                Text(typeLabel + " · " + cat.label, { fontSize: 13, fontWeight: "600", color: amountColor })
              )
          ])
        ),
        infoRow("Catégorie", cat.label),
        infoRow("Date", fmtDate(t.date)),
        infoRow("Note", noteText),
        Button("Modifier", { onTap: "edit", color: T.primary, fullWidth: true, icon: "edit" }),
        Button("Supprimer", { onTap: "remove", variant: "outlined", color: T.danger, fullWidth: true, icon: "delete" })
    ])
  )
}

fn infoRow(label, value) {
  return Box({ color: T.surface, borderRadius: 14, padding: 16, borderColor: T.line, borderWidth: 1 },
    Row({ mainAxisAlignment: "spaceBetween", crossAxisAlignment: "center", spacing: 12 }, [
        Text(label, { fontSize: 13, color: T.muted }),
        Text(value, { fontSize: 14, fontWeight: "600", color: T.text })
    ])
  )
}
