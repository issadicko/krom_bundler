// ============================================================
// État réactif partagé du Wallet + handlers génériques.
// (Importé par tous les composants via @use.)
// ============================================================

// Détail d'opération (sheet)
let selectedTxId = ""
let excludeAnalytics = Obs(false)

// Comptes / carte
let currentAccount = Obs(0)
let freeze = Obs(false)

// Version des données (solde + opérations) — déclencheur de rebuild.
let tick = Obs(0)

// Transfert (sheet)
let transferContact = null
let transferAmount = ""
let transferNote = ""

// Marketplace (enchaînement liste -> détail)
let marketView = Obs("list")   // "list" | "detail"
let selectedOffer = null
let marketCat = Obs("all")     // filtre catégorie
let activated = Obs(false)     // offre courante activée

fn noop() {}
fn closeSheet() { ui.pop() }
