// ============================================================
// Wallet — prototype néobanque.
// Page = simple coquille : TabHostNav flottant. Tout le contenu est
// découpé en composants importés via @use (utils/components/*).
// ============================================================
@use "../utils/ui.ks"
@use "../utils/components/home_view.ks"
@use "../utils/components/move_view.ks"
@use "../utils/components/cards_view.ks"
@use "../utils/components/market_view.ks"
@use "../utils/components/profile_view.ks"

fn build() {
  return Scaffold({ backgroundColor: T.bg },
    TabHostNav({
        floating: true,
        showLabels: false,
        backgroundColor: T.card,
        selectedColor: T.text,
        unselectedColor: T.muted,
        tabs: [
          { icon: "home",    builder: "homeTab" },
          { icon: "sync",    builder: "moveTab" },
          { icon: "payment", builder: "cardsTab" },
          { icon: "store",   builder: "shopTab" },
          { icon: "person",  builder: "meTab" }
        ]
    })
  )
}
