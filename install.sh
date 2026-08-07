#!/bin/sh
# Krom CLI installer — downloads the right native binary for your OS/arch.
#
#   curl -fsSL https://raw.githubusercontent.com/issadicko/krom_bundler/main/install.sh | sh
#
# Env overrides:
#   KROM_VERSION      version tag to install (default: latest), e.g. v0.1.0
#   KROM_INSTALL_DIR  install directory (default: /usr/local/bin, else ~/.local/bin)
set -eu

REPO="issadicko/krom_bundler"
BIN="krom"
VERSION="${KROM_VERSION:-latest}"

say()  { printf '%s\n' "$*"; }
err()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$*"; }

# --- detect platform ---------------------------------------------------------
os="$(uname -s)"
case "$os" in
  Darwin) os="darwin" ;;
  Linux)  os="linux" ;;
  *) err "OS non supporté : $os (macOS et Linux uniquement). Sur Windows, télécharge krom-windows-x64.exe depuis les Releases." ;;
esac

arch="$(uname -m)"
case "$arch" in
  x86_64|amd64)  arch="x64" ;;
  arm64|aarch64) arch="arm64" ;;
  *) err "Architecture non supportée : $arch" ;;
esac

asset="krom-${os}-${arch}"

# --- resolve download URLs ---------------------------------------------------
if [ "$VERSION" = "latest" ]; then
  base="https://github.com/${REPO}/releases/latest/download"
else
  base="https://github.com/${REPO}/releases/download/${VERSION}"
fi

# --- http helper -------------------------------------------------------------
if command -v curl >/dev/null 2>&1; then
  fetch() { curl -fSL "$1" -o "$2"; }
elif command -v wget >/dev/null 2>&1; then
  fetch() { wget -qO "$2" "$1"; }
else
  err "curl ou wget est requis."
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say "→ Téléchargement de ${asset} (${VERSION})…"
fetch "${base}/${asset}" "${tmp}/${BIN}" \
  || err "Téléchargement impossible (${base}/${asset}). La release existe-t-elle pour ${os}-${arch} ?"

# --- verify checksum (best-effort) -------------------------------------------
if fetch "${base}/${asset}.sha256" "${tmp}/sum" 2>/dev/null; then
  expected="$(awk '{print $1}' "${tmp}/sum")"
  if [ -n "${expected:-}" ]; then
    if command -v sha256sum >/dev/null 2>&1; then
      actual="$(sha256sum "${tmp}/${BIN}" | awk '{print $1}')"
    else
      actual="$(shasum -a 256 "${tmp}/${BIN}" | awk '{print $1}')"
    fi
    [ "$expected" = "$actual" ] || err "Checksum invalide (attendu ${expected}, obtenu ${actual})."
    ok "Checksum vérifié."
  fi
fi

chmod +x "${tmp}/${BIN}"

# --- choose install dir ------------------------------------------------------
if [ -n "${KROM_INSTALL_DIR:-}" ]; then
  dir="$KROM_INSTALL_DIR"
elif [ -w /usr/local/bin ] 2>/dev/null; then
  dir="/usr/local/bin"
else
  dir="${HOME}/.local/bin"
fi

mkdir -p "$dir" 2>/dev/null || true

if [ -w "$dir" ] 2>/dev/null; then
  mv "${tmp}/${BIN}" "${dir}/${BIN}"
elif command -v sudo >/dev/null 2>&1; then
  say "→ ${dir} requiert des privilèges élevés…"
  sudo mkdir -p "$dir" && sudo mv "${tmp}/${BIN}" "${dir}/${BIN}"
else
  err "${dir} non accessible en écriture et sudo indisponible. Définis KROM_INSTALL_DIR."
fi

ok "krom installé dans ${dir}"

"${dir}/${BIN}" --version 2>/dev/null || true

# --- PATH hint (shell-aware) -------------------------------------------------
# Le binaire est installé, mais encore faut-il que ${dir} soit dans le PATH du
# shell de l'utilisateur. On adapte la commande au shell — surtout fish, qui
# n'a pas `export` et gère son PATH à part (une session fraîche peut manquer
# ${dir} même si ce processus sh l'a hérité).
shell_name="$(basename "${SHELL:-sh}")"

on_path=0
case ":${PATH}:" in *":${dir}:"*) on_path=1 ;; esac
if [ "$shell_name" = "fish" ] && command -v fish >/dev/null 2>&1; then
  if fish -c "contains -- '${dir}' \$PATH" >/dev/null 2>&1; then
    on_path=1
  else
    on_path=0
  fi
fi

if [ "$on_path" -eq 0 ]; then
  say ""
  say "⚠ ${dir} n'est pas dans le PATH de ton shell (${shell_name})."
  case "$shell_name" in
    fish) say "  Ajoute-le (persistant) :  fish_add_path ${dir}" ;;
    zsh)  say "  Ajoute à ~/.zshrc :  export PATH=\"${dir}:\$PATH\"" ;;
    bash) say "  Ajoute à ~/.bashrc :  export PATH=\"${dir}:\$PATH\"" ;;
    *)    say "  Ajoute à la config de ton shell :  export PATH=\"${dir}:\$PATH\"" ;;
  esac
  say "  Puis rouvre un terminal."
fi
