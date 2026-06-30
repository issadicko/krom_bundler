// ============================================================
// Bottom sheet : détail d'une opération (statut, analytics, BarChart).
// ============================================================
@use "../ui.ks"
@use "../data.ks"
@use "../state.ks"
@use "./shared.ks"

fn openTx(id) {
  selectedTxId = id
  excludeAnalytics.set(false)
  ui.showBottomSheet("txDetailSheet")
}

fn txDetailSheet() {
  let t = txById(selectedTxId)
  if (t == null) {
    return Box({ padding: 24 }, Text("Introuvable", { color: T.muted }))
  }
  let amtColor = T.text
  if (t.amount >= 0) { amtColor = T.income }

  return Box({ height: 560 },
    ScrollView({ padding: { left: 16, right: 16, top: 0, bottom: 8 } },
      Column({ crossAxisAlignment: "stretch", spacing: 16 }, [
          sheetHeader(),
          Center(
            Column({ crossAxisAlignment: "center", spacing: 8 }, [
                avatarCircle(t.emoji, t.color, 64),
                Text(t.name, { fontSize: 20, fontWeight: "bold", color: T.text }),
                Text(t.time, { fontSize: 13, color: T.muted }),
                Text(signedUsd(t.amount), { fontSize: 34, fontWeight: "bold", color: amtColor })
            ])
          ),
          statusCard(t),
          Obx({ builder: "analyticsCard" }),
          spendingCard()
      ])
    )
  )
}

fn statusCard(t) {
  let rows = [
    detailRow("Status", statusBadge(t.status)),
    detailRow("Confirmation", downloadLink())
  ]
  if (t.card != "") {
    rows.add(detailRow("Card", cardChip(t.card)))
  }
  return card(Column({ spacing: 14 }, rows))
}

fn statusBadge(status) {
  return Box({ color: alpha(T.income, "1F"), borderRadius: 14, padding: { left: 12, right: 12, top: 6, bottom: 6 } },
    Text(status, { fontSize: 13, fontWeight: "600", color: T.income })
  )
}

fn downloadLink() {
  return Row({ spacing: 6, crossAxisAlignment: "center" }, [
      Icon("download", { size: 18, color: T.text }),
      Text("Download", { fontSize: 14, fontWeight: "600", color: T.text })
  ])
}

fn cardChip(num) {
  return Row({ spacing: 8, crossAxisAlignment: "center" }, [
      Box({ width: 26, height: 18, borderRadius: 4, color: alpha(T.text, "14") }),
      Text("•• " + num, { fontSize: 14, fontWeight: "600", color: T.text })
  ])
}

fn analyticsCard() {
  let t = txById(selectedTxId)
  let excluded = excludeAnalytics.value
  let amt = 0
  let catLabel = "—"
  if (t != null) {
    amt = t.amount
    if (amt < 0) { amt = -amt }
    catLabel = t.category
  }
  return card(Column({ spacing: 14 }, [
        Row({ mainAxisAlignment: "spaceBetween", crossAxisAlignment: "center" }, [
            Text("Exclude from analytics", { fontSize: 14, color: T.text }),
            Switch({ value: excluded, onChanged: "toggleExclude", activeColor: T.text })
        ]),
        detailRow("Category", catRow(catLabel)),
        detailRow("Amount in analytics", editAmount(amt))
  ]))
}

fn toggleExclude(v) { excludeAnalytics.set(v) }

fn catRow(label) {
  return Row({ spacing: 8, crossAxisAlignment: "center" }, [
      Text("🍽️", { fontSize: 16 }),
      Text(label, { fontSize: 14, fontWeight: "600", color: T.text })
  ])
}

fn editAmount(amt) {
  return Row({ spacing: 8, crossAxisAlignment: "center" }, [
      Icon("edit", { size: 16, color: T.muted }),
      Text(usd(amt), { fontSize: 14, fontWeight: "600", color: T.text })
  ])
}

fn spendingCard() {
  let total = 0
  SPENDING.forEach(fn(s, i) { total = total + s.value })
  return card(Column({ crossAxisAlignment: "stretch", spacing: 14 }, [
        Row({ mainAxisAlignment: "spaceBetween", crossAxisAlignment: "center" }, [
            Text("Half-year spending", { fontSize: 15, fontWeight: "600", color: T.text }),
            Text(usd(total), { fontSize: 15, fontWeight: "bold", color: T.text })
        ]),
        BarChart({
            height: 140,
            yGridLines: 2,
            valuePrefix: "$",
            barColor: T.ink,
            trackColor: alpha(T.text, "0F"),
            data: SPENDING
        })
  ]))
}
