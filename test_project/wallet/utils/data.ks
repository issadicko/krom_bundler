// ============================================================
// Wallet — données de démonstration (statiques, prototype).
// ============================================================

let ACCOUNT = { label: "USD Personal", balance: 12386.40 }

// Comptes pour le carrousel (PageView).
let ACCOUNTS = [
  { label: "USD Personal", balance: 12386.40, sym: "$" },
  { label: "EUR Savings",  balance: 4920.00,  sym: "€" },
  { label: "GBP Travel",   balance: 845.75,   sym: "£" }
]

// Ordonné du plus ancien au plus récent : l'affichage utilise reverse(TX),
// donc les ajouts (transferts) apparaissent en tête.
let TX = [
  { id: "t5", name: "Uber",            emoji: "🚗", color: "#111827", time: "Mar 01, 21:13",    amount: -18.40, category: "Transport",            status: "Completed", card: "2675" },
  { id: "t4", name: "Spotify",         emoji: "🎵", color: "#10B981", time: "Mar 02, 12:00",    amount: -9.99,  category: "Subscriptions",        status: "Completed", card: "2675" },
  { id: "t3", name: "Whole Foods",     emoji: "🛒", color: "#22C55E", time: "Yesterday, 18:04", amount: -84.20, category: "Groceries",            status: "Completed", card: "2675" },
  { id: "t2", name: "Astra Coffeebar", emoji: "☕", color: "#F59E0B", time: "Today, 08:32",     amount: -21.50, category: "Cafes & Restaurants",  status: "Completed", card: "2675" },
  { id: "t1", name: "Alexa Turner",    emoji: "🧑", color: "#6366F1", time: "Today, 23:27",     amount: 50.00,  category: "Transfer",             status: "Completed", card: "" }
]

fn txById(id) {
  let found = null
  TX.forEach(fn(t, i) { if (t.id == id) { found = t } })
  return found
}

// Contacts pour l'onglet « Move ».
let CONTACTS = [
  { name: "Alexa", emoji: "🧑", color: "#6366F1" },
  { name: "Sam",   emoji: "🧔", color: "#0EA5E9" },
  { name: "Lina",  emoji: "👩", color: "#EC4899" },
  { name: "Theo",  emoji: "🧑", color: "#22C55E" }
]

// Offres pour l'onglet « Marketplace ».
let OFFER_CATS = [
  { key: "food",   label: "Food" },
  { key: "shop",   label: "Shopping" },
  { key: "travel", label: "Travel" },
  { key: "media",  label: "Media" }
]

let OFFERS = [
  { id: "o1", brand: "Astra Coffee", perk: "5% cashback",   emoji: "☕", color: "#F59E0B", cat: "food",   desc: "Gagnez 5% sur chaque café réglé avec votre carte Wallet, dans tous les Astra Coffeebar." },
  { id: "o2", brand: "Whole Foods",  perk: "3% cashback",   emoji: "🛒", color: "#22C55E", cat: "food",   desc: "3% reversés automatiquement sur vos courses Whole Foods." },
  { id: "o3", brand: "Uber",         perk: "$5 back",       emoji: "🚗", color: "#111827", cat: "travel", desc: "5 $ remboursés après 3 trajets Uber effectués ce mois-ci." },
  { id: "o4", brand: "Spotify",      perk: "1 mois offert", emoji: "🎵", color: "#10B981", cat: "media",  desc: "1 mois de Spotify Premium offert pour tout nouvel abonnement." },
  { id: "o5", brand: "Nike",         perk: "10% off",       emoji: "👟", color: "#6366F1", cat: "shop",   desc: "10% de réduction immédiate sur Nike.com avec votre carte Wallet." },
  { id: "o6", brand: "Booking",      perk: "8% cashback",   emoji: "🏨", color: "#0EA5E9", cat: "travel", desc: "8% de cashback sur vos réservations d'hôtel via Booking." }
]

// Dépenses mensuelles (somme = 630.96, comme la maquette).
let SPENDING = [
  { label: "Jan", value: 88.40 },
  { label: "Feb", value: 95.10 },
  { label: "Mar", value: 132.50 },
  { label: "Apr", value: 140.20 },
  { label: "May", value: 92.30 },
  { label: "Jun", value: 82.46 }
]
