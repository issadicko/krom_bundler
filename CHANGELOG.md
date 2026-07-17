## 0.2.0

### Templates `krom init`

- **3 nouveaux templates** : `form` (champs + Select + Switch + résumé réactif + envoi), `dashboard` (cartes de stats + BarChart + Gauge) et `onboarding` (carrousel PageView + points + bouton).
- **Templates existants améliorés** : `default` entièrement **thématisé** (suit le thème clair/sombre de l'hôte) et débarrassé du champ `utils` déprécié du manifeste ; `tabbed` gagne des libellés d'onglets + une carte solde ; `list-detail` gagne une AppBar.
- Tous les templates sont vérifiés au rendu sur le preview Galaxy S24 et bundlés par la CI (`init_templates_test.dart`).

### Preview

- **Preview embarqué régénéré** (`preview_assets.g.dart`) contre `krom_script 1.0.1` : le runtime du preview supporte désormais l'**opérateur ternaire `? :`** (et le reste de la syntaxe 1.0).

## 0.1.1

- Dépendance `krom_script` résolue depuis **pub.dev** (au lieu du dépôt git krom-lang) — la CI n'a plus besoin d'accéder au repo pour construire les binaires.

## 0.1.0

- Distribution binaire multi-OS + installeur `curl | sh`.
- Initial version.
