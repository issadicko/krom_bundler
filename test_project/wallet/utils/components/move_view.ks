// ============================================================
// Onglet Move : actions Send/Request, contacts, transfert fonctionnel
// (bottom sheet qui modifie réellement le solde + les opérations).
// ============================================================
@use "../ui.ks"
@use "../data.ks"
@use "../state.ks"
@use "./shared.ks"

fn moveTab() {
  return tabScreen("Move money", [
      Row({ spacing: 12 }, [
          Expanded({ flex: 1 }, bigAction("Send", "send", "startSend")),
          Expanded({ flex: 1 }, bigAction("Request", "download", "startRequest"))
      ]),
      Text("Recent", { fontSize: 15, fontWeight: "600", color: T.text }),
      contactsRow(),
      listCard(recentMoves())
  ])
}

fn bigAction(label, icon, cb) {
  return InkWell({ onTap: cb, borderRadius: 20 },
    Box({ color: T.card, borderRadius: 20, padding: { left: 16, right: 16, top: 18, bottom: 18 } },
      Column({ crossAxisAlignment: "center", spacing: 8 }, [
          Box({ width: 44, height: 44, borderRadius: 22, color: T.ink },
            Center(Icon(icon, { size: 20, color: T.onInk }))
          ),
          Text(label, { fontSize: 14, fontWeight: "600", color: T.text })
      ])
    )
  )
}

fn contactsRow() {
  let chips = []
  CONTACTS.forEach(fn(c, i) { chips.add(contactChip(c)) })
  return ScrollView({ direction: "horizontal" },
    Row({ spacing: 16 }, chips)
  )
}

fn contactChip(c) {
  return InkWell({ onTap: "openTransfer", arg: c, borderRadius: 14 },
    Column({ crossAxisAlignment: "center", spacing: 6 }, [
        avatarCircle(c.emoji, c.color, 52),
        Text(c.name, { fontSize: 12, color: T.text })
    ])
  )
}

fn recentMoves() {
  let v = tick.value
  let list = reverse(TX)
  let rows = []
  let i = 0
  while (i < list.length) {
    if (i < 3) { rows.add(opRow(list[i])) }
    i = i + 1
  }
  return Column({ spacing: 14 }, rows)
}

// --- Transfert (sheet) ---------------------------------------
fn startSend() { openTransfer(CONTACTS[0]) }
fn startRequest() { ui.toast("Demande de paiement — bientôt") }

fn openTransfer(c) {
  transferContact = c
  transferAmount = ""
  transferNote = ""
  ui.showBottomSheet("transferSheet")
}

fn onTransferAmount(v) { transferAmount = v }
fn onTransferNote(v) { transferNote = v }

fn doTransfer() {
  let amount = toNumber(replace(transferAmount, ",", "."))
  if (amount == null) { ui.toast("Montant invalide")  return }
  if (amount <= 0) { ui.toast("Montant invalide")  return }
  let idx = currentAccount.value
  let acct = ACCOUNTS[idx]
  if (amount > acct.balance) {
    ui.toast("Solde insuffisant")
    return
  }
  setProperty(acct, "balance", acct.balance - amount)
  TX.add({
      id: randomUUID(),
      name: transferContact.name,
      emoji: transferContact.emoji,
      color: transferContact.color,
      time: "À l'instant",
      amount: 0 - amount,
      category: "Transfer",
      status: "Completed",
      card: ""
  })
  tick.set(tick.value + 1)
  ui.toast("Envoyé " + fmtMoney(amount, acct.sym) + " à " + transferContact.name)
  ui.pop()
}

fn transferSheet() {
  let c = transferContact
  if (c == null) {
    return Box({ padding: 24 }, Text("—", { color: T.muted }))
  }
  let acct = ACCOUNTS[currentAccount.value]
  return Box({ height: 470 },
    ScrollView({ padding: { left: 16, right: 16, top: 0, bottom: 8 } },
      Column({ crossAxisAlignment: "stretch", spacing: 16 }, [
          sheetHeader(),
          Center(
            Column({ crossAxisAlignment: "center", spacing: 8 }, [
                avatarCircle(c.emoji, c.color, 60),
                Text("Envoyer à " + c.name, { fontSize: 18, fontWeight: "bold", color: T.text }),
                Text("Depuis " + acct.label + " · " + fmtMoney(acct.balance, acct.sym), { fontSize: 13, color: T.muted })
            ])
          ),
          card(Column({ spacing: 14, crossAxisAlignment: "start" }, [
                Text("Montant (" + acct.sym + ")", { fontSize: 14, fontWeight: "bold", color: T.text }),
                TextField({ labelText: "0.00", value: transferAmount, onChange: "onTransferAmount", keyboardType: "number", prefixIcon: "payment", backgroundColor: T.cardAlt }),
                TextField({ labelText: "Note (optionnel)", value: transferNote, onChange: "onTransferNote", backgroundColor: T.cardAlt })
          ])),
          Button("Envoyer", { onTap: "doTransfer", color: T.ink, fullWidth: true, icon: "send" })
      ])
    )
  )
}
