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
if fetch "${base}/SHA256SUMS" "${tmp}/SHA256SUMS" 2>/dev/null; then
  expected="$(grep " ${asset}\$" "${tmp}/SHA256SUMS" 2>/dev/null | awk '{print $1}')"
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

# --- PATH hint ---------------------------------------------------------------
case ":${PATH}:" in
  *":${dir}:"*) ;;
  *) say "⚠ ${dir} n'est pas dans ton PATH. Ajoute :  export PATH=\"${dir}:\$PATH\"" ;;
esac

"${dir}/${BIN}" --version 2>/dev/null || true
