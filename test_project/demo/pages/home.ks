// ============================================================
// SDK Demo — showcase des features récentes :
// custom widget hôte, bindings (function + module gated), résultat
// (ui.finish), ui.confirm / ui.snack / ui.track, et les widgets P1/P2.
// ============================================================
@use "../utils/ui.ks"
@use "../utils/state.ks"

fn build() {
  return ScrollView({ padding: { left: 16, right: 16, top: 16, bottom: 28 } },
    Column({ crossAxisAlignment: "stretch", spacing: 4 }, [
        Text("SDK Demo", { fontSize: 26, fontWeight: "bold", color: T.text }),
        Text("Toutes les features récentes du SDK.", { fontSize: 14, color: T.muted }),
        SizedBox({ height: 16 }),
        hostCard(),
        inputCard(),
        displayCard(),
        actionsCard()
    ])
  )
}

// --- Hôte : custom widget + bindings -------------------------
// Les bindings hôte (share / vault) ne sont appelés que sur ACTION, jamais au
// build : la page s'affiche donc même sur un hôte qui ne les fournit pas (preview).
fn hostCard() {
  return card(Column({ crossAxisAlignment: "stretch", spacing: 14 }, [
      sectionTitle("HÔTE (bindings + custom widget)"),
      Row({ crossAxisAlignment: "center", spacing: 10 }, [
          DemoBadge({ text: "Custom host widget", color: "#7C3AED" })
      ]),
      Obx({ builder: "vaultLine" }),
      Row({ spacing: 10 }, [
          Expanded({ flex: 1 }, Button("Lire le coffre", { onTap: "doVault", icon: "lock", variant: "outlined", fullWidth: true })),
          Expanded({ flex: 1 }, Button("Partager", { onTap: "doShare", icon: "share", variant: "outlined", fullWidth: true }))
      ]),
      Button("Envoyer un événement (track)", { onTap: "doTrack", variant: "text", color: T.primary })
  ]))
}

fn vaultLine() { return resultChip("vault: " + vaultVal.value) }
fn doVault() { vaultVal.set(vault.get())  ui.toast("vault.get() lu") }

// --- Saisie : widgets P1 -------------------------------------
fn inputCard() {
  return card(Column({ crossAxisAlignment: "stretch", spacing: 16 }, [
      sectionTitle("SAISIE (Select, Radio, Chip, Segmented, Date)"),
      Obx({ builder: "currencyField" }),
      Obx({ builder: "planField" }),
      Obx({ builder: "chipField" }),
      Obx({ builder: "segField" }),
      Obx({ builder: "dateField" })
  ]))
}

fn currencyField() {
  return field("Devise", Select({ value: selCur.value, onChange: "onCur", prefixIcon: "payment", options: [
      { label: "EUR €", value: "eur" },
      { label: "USD $", value: "usd" },
      { label: "XOF", value: "xof" }
  ] }))
}

fn planField() {
  return field("Formule", RadioGroup({ value: radio.value, onChange: "onRadio", options: [
      { label: "Standard", value: "std" },
      { label: "Express", value: "exp" }
  ] }))
}

fn chipField() {
  let cur = chipSel.value
  return field("Filtre (Chip + Wrap)", Wrap({ spacing: 8, runSpacing: 8 }, [
      Chip("Toutes", { selected: cur == "all", onTap: "pickChip", arg: "all" }),
      Chip("Perso", { selected: cur == "perso", onTap: "pickChip", arg: "perso" }),
      Chip("Pro", { selected: cur == "pro", onTap: "pickChip", arg: "pro" })
  ]))
}

fn segField() {
  return field("Période (Segmented)", Segmented({ value: seg.value, onChange: "onSeg", options: [
      { label: "Mois", value: "month" },
      { label: "Année", value: "year" }
  ] }))
}

fn dateField() {
  let v = dateVal.value
  let shown = v
  if (v == "") { shown = "—" }
  return field("Date (" + shown + ")", DateField({ value: v, onChange: "onDate", label: "Choisir une date" }))
}

// --- Affichage : widgets P2 ----------------------------------
fn displayCard() {
  return card(Column({ crossAxisAlignment: "stretch", spacing: 16 }, [
      sectionTitle("AFFICHAGE (Avatar, Badge, Progress, Expansion, Swipe)"),
      Row({ crossAxisAlignment: "center", spacing: 14 }, [
          Avatar({ text: "AT", size: 44, color: "#6366F1" }),
          Badge({ count: 3 }, Icon("notifications", { size: 28, color: T.text })),
          Expanded({ flex: 1 }, Obx({ builder: "progressLine" }))
      ]),
      Button("Avancer la progression", { onTap: "bumpProgress", variant: "text", color: T.primary }),
      ExpansionTile({ title: "Détails (ExpansionTile)", icon: "info" }, [
          Text("Contenu repliable rendu à la demande.", { fontSize: 14, color: T.muted })
      ]),
      Obx({ builder: "swipeRow" })
  ]))
}

fn progressLine() {
  return Column({ crossAxisAlignment: "stretch", spacing: 6 }, [
      LinearProgress({ value: progress.value, height: 10, color: T.primary }),
      Text("Progression : " + progress.value, { fontSize: 12, color: T.muted })
  ])
}

fn swipeRow() {
  if (removed.value) {
    return resultChip("Ligne supprimée (swipe) ✓")
  }
  return Swipeable({ id: "demo-row", onDismiss: "onRemoved", background: "#DC2626", icon: "delete" },
    Box({ color: T.cardAlt, borderRadius: 12, padding: 14 },
      Row({ crossAxisAlignment: "center", spacing: 12 }, [
          Icon("swipe", { size: 20, color: T.muted }),
          Text("Glisse vers la gauche pour supprimer", { fontSize: 14, color: T.text })
      ])
    )
  )
}

// --- Actions : confirm / snack / résultat --------------------
fn actionsCard() {
  return card(Column({ crossAxisAlignment: "stretch", spacing: 10 }, [
      sectionTitle("ACTIONS (confirm, snack, résultat)"),
      Button("Confirmer une action", { onTap: "doConfirm", variant: "outlined", fullWidth: true }),
      Button("Supprimer (snack Undo)", { onTap: "doSnack", variant: "outlined", color: T.danger, fullWidth: true }),
      Button("Valider et fermer", { onTap: "doFinish", color: T.primary, fullWidth: true })
  ]))
}

fn doShare() { share("Bonjour depuis la mini-app démo !")  ui.toast("share() appelé") }
fn doTrack() { ui.track("cta_clicked", { source: "demo", currency: selCur.value })  ui.toast("ui.track envoyé") }

fn doConfirm() {
  ui.confirm({ title: "Confirmer ?", message: "Démo de ui.confirm.", confirmLabel: "Oui", cancelLabel: "Non", onConfirm: "onConfirmed" })
}
fn onConfirmed() { ui.toast("Confirmé ✓") }

fn doSnack() { ui.snack({ message: "Élément supprimé", actionLabel: "Annuler", onAction: "onUndo" }) }
fn onUndo() { ui.toast("Restauré ↩") }

// Renvoie un résultat à l'hôte (Krom.open -> Future).
fn doFinish() { ui.finish({ ok: true, currency: selCur.value, plan: radio.value }) }
