# krom — CLI des mini-apps Krom

Outil en ligne de commande pour créer, prévisualiser, bundler et déployer des
mini-apps Krom écrites en KromScript.

## Installation

### macOS / Linux (recommandé)

```sh
curl -fsSL https://raw.githubusercontent.com/issadicko/krom_bundler/main/install.sh | sh
```

Le script détecte ton OS et ton architecture (macOS/Linux, x64/arm64), télécharge
le binaire natif correspondant, vérifie son empreinte SHA-256 et l'installe dans
`/usr/local/bin` (ou `~/.local/bin` sinon).

Options :

```sh
# Épingler une version
curl -fsSL https://raw.githubusercontent.com/issadicko/krom_bundler/main/install.sh | KROM_VERSION=v0.1.0 sh

# Choisir le dossier d'installation
curl -fsSL https://raw.githubusercontent.com/issadicko/krom_bundler/main/install.sh | KROM_INSTALL_DIR="$HOME/bin" sh
```

### Windows

Télécharge `krom-windows-x64.exe` depuis la [dernière release](https://github.com/issadicko/krom_bundler/releases/latest),
renomme-le en `krom.exe` et place-le dans un dossier de ton `PATH`.

### Depuis les sources (nécessite le SDK Dart)

```sh
dart pub global activate --source git https://github.com/issadicko/krom_bundler.git
```

### Vérifier

```sh
krom --version
krom --help
```

## Commandes principales

| Commande | Rôle |
|----------|------|
| `krom init` | Créer un projet de mini-app (templates disponibles) |
| `krom dev` | Serveur de dev + hot reload + QR pour Krom Go |
| `krom build` / `krom bundle` | Compiler / empaqueter la mini-app |
| `krom login` / `krom logout` / `krom whoami` | Authentification backend |
| `krom deploy` | Publier et déployer une version |

## Développement

```sh
dart pub get
dart run bin/krom_bundler.dart --help
```

La publication des binaires est automatisée : pousser un tag `vX.Y.Z` déclenche
le workflow [`release.yml`](.github/workflows/release.yml) qui compile `krom`
pour macOS (arm64/x64), Linux (x64/arm64) et Windows (x64). Chaque plateforme
attache **indépendamment** son binaire (+ son `.sha256`) à la Release GitHub —
un runner lent ou indisponible ne bloque donc pas les autres.

## Licence

MIT — voir [LICENSE](LICENSE).
