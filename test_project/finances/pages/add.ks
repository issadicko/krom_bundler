// ============================================================
// Ajouter / Modifier — type (dépense/revenu), montant, catégorie, note.
// En mode édition, `args.id` (fourni par ui.push depuis le Détail) pré-remplit
// le formulaire au chargement, avant le premier build.
// ============================================================
@use "../utils/ui.ks"
@use "../utils/store.ks"

let editingId = ""
let txType = Obs("expense")
let category = Obs("food")
let amountStr = ""
let note = ""

// Pré-remplissage en mode édition. `args` est toujours défini (null si la page
// a été ouverte sans paramètres).
if (args != null) {
  if (args.id != null) {
    let _t = txById(args.id)
    if (_t != null) {
      editingId = _t.id
      txType.set(_t.type)
      category.set(_t.category)
      amountStr = numToInput(_t.amount)
      note = _t.note
    }
  }
}

fn isEditing() { return editingId != "" }
fn screenTitle() {
  if (isEditing()) { return "Modifier" }
  return "Nouvelle transaction"
}

fn onAmount(v) { amountStr = v }
fn onNote(v) { note = v }
fn cancel() { ui.pop() }

fn setType(tp) {
  txType.set(tp)
  // Bascule sur une catégorie par défaut cohérente avec le type.
  if (tp == "income") {
    category.set("salary")
  } else {
    category.set("food")
  }
}

fn setCategory(k) { category.set(k) }

// Accepte "12,50" comme "12.50".
fn parseAmount(s) {
  return toNumber(replace(s, ",", "."))
}

fn save() {
  let amount = parseAmount(amountStr)
  if (amount == null) {
    ui.toast("Montant invalide")
    return
  }
  if (amount <= 0) {
    ui.toast("Montant invalide")
    return
  }
  if (isEditing()) {
    updateTx(editingId, txType.value, amount, category.value, note)
    ui.toast("Transaction modifiée")
  } else {
    addTx(txType.value, amount, category.value, note)
    ui.toast("Transaction ajoutée")
  }
  ui.pop()
}

fn build() {
  return Scaffold({
      appBar: AppBar({ title: screenTitle(), backgroundColor: T.primary }),
      backgroundColor: T.bg
    },
    ScrollView({ padding: 16 },
      Column({ spacing: 16, crossAxisAlignment: "start" }, [
          Obx({ builder: "typeToggle" }),
          Card({ borderRadius: 16, padding: 16, color: T.surface },
            Column({ spacing: 14, crossAxisAlignment: "start" }, [
                Text("Montant", { fontSize: 14, fontWeight: "bold", color: T.text }),
                TextField({ labelText: "0,00 €", value: amountStr, onChange: "onAmount", keyboardType: "number", backgroundColor: T.surface }),
                TextField({ labelText: "Note (optionnel)", value: note, onChange: "onNote", backgroundColor: T.surface })
            ])
          ),
          Text("Catégorie", { fontSize: 14, fontWeight: "bold", color: T.text }),
          Obx({ builder: "categoryGrid" }),
          Button(saveLabel(), { onTap: "save", color: T.primary, fullWidth: true, icon: "save" }),
          Button("Annuler", { onTap: "cancel", variant: "text", color: T.muted, fullWidth: true })
      ])
    )
  )
}

fn saveLabel() {
  if (isEditing()) { return "Enregistrer les modifications" }
  return "Enregistrer"
}

fn typeToggle() {
  let tp = txType.value
  return Row({ spacing: 10 }, [
      Expanded({ flex: 1 }, typeOption("Dépense", "expense", tp, T.expense)),
      Expanded({ flex: 1 }, typeOption("Revenu", "income", tp, T.income))
  ])
}

fn typeOption(label, value, current, col) {
  let bg = T.surface
  let fg = T.text
  let border = T.line
  if (value == current) {
    bg = col
    fg = "#FFFFFF"
    border = col
  }
  return InkWell({ onTap: "setType", arg: value, borderRadius: 12 },
    Box({ color: bg, borderRadius: 12, padding: 14, borderColor: border, borderWidth: 1 },
      Center(Text(label, { fontSize: 14, fontWeight: "600", color: fg }))
    )
  )
}

// Grille des catégories du type courant, en rangées de 2.
fn categoryGrid() {
  let tp = txType.value
  let cur = category.value
  let cats = categoriesFor(tp)
  let rows = []
  let i = 0
  let n = cats.length
  while (i < n) {
    let cells = [ Expanded({ flex: 1 }, categoryCell(cats[i], cur)) ]
    if (i + 1 < n) {
      cells.add(Expanded({ flex: 1 }, categoryCell(cats[i + 1], cur)))
    } else {
      cells.add(Expanded({ flex: 1 }, Box({})))
    }
    rows.add(Row({ spacing: 10 }, cells))
    i = i + 2
  }
  return Column({ spacing: 10 }, rows)
}

fn categoryCell(cat, cur) {
  let bg = T.surface
  let border = T.line
  if (cat.key == cur) {
    bg = T.chipBg
    border = T.primary
  }
  return InkWell({ onTap: "setCategory", arg: cat.key, borderRadius: 12 },
    Box({ color: bg, borderRadius: 12, padding: 10, borderColor: border, borderWidth: 1 },
      Row({ spacing: 10, crossAxisAlignment: "center" }, [
          catAvatar(cat, 34),
          Expanded({ flex: 1 }, Text(cat.label, { fontSize: 13, fontWeight: "600", color: T.text }))
      ])
    )
  )
}
