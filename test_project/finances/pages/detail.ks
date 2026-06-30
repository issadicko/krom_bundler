// ============================================================
// Détail d'une transaction (+ suppression). `args.id` vient de ui.push.
// Obs(null) étant piégeux en KromScript, on garde l'id en variable et
// on utilise `tick` (Obs entier) comme simple déclencheur de rebuild.
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
  let badgeBg = T.expenseBg
  if (t.type == "income") {
    amountColor = T.income
    typeLabel = "Revenu"
    badgeBg = T.incomeBg
  }

  let noteText = t.note
  if (noteText == "") { noteText = "—" }

  return ScrollView({ padding: 16 },
    Column({ spacing: 16, crossAxisAlignment: "start" }, [
        Card({ borderRadius: 16, padding: 20, color: T.surface },
          Column({ spacing: 12, crossAxisAlignment: "center", mainAxisAlignment: "center" }, [
              catAvatar(cat, 64),
              Text(signedMoney(t.amount, t.type), { fontSize: 30, fontWeight: "bold", color: amountColor }),
              Box({ color: badgeBg, borderRadius: 20, padding: 8 },
                Text(typeLabel + " · " + cat.label, { fontSize: 13, fontWeight: "600", color: amountColor })
              )
          ])
        ),
        infoRow("Catégorie", cat.label),
        infoRow("Date", fmtDate(t.date)),
        infoRow("Note", noteText),
        Button("Supprimer", { onTap: "remove", color: T.danger, fullWidth: true, icon: "delete" })
    ])
  )
}

fn infoRow(label, value) {
  return Box({ color: T.surface, borderRadius: 14, padding: 16 },
    Row({ mainAxisAlignment: "spaceBetween", crossAxisAlignment: "center", spacing: 12 }, [
        Text(label, { fontSize: 13, color: T.muted }),
        Text(value, { fontSize: 14, fontWeight: "600", color: T.text })
    ])
  )
}
