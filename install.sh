#!/bin/bash
# Samune installer.
#   curl -fsSL https://raw.githubusercontent.com/drarekx/Samune/main/install.sh | bash
set -euo pipefail

NAME="Samune"
REPO="drarekx/Samune"
URL="https://github.com/$REPO/releases/latest/download/${NAME}.zip"

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
fail() { printf "\033[31mError:\033[0m %s\n" "$*" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || fail "$NAME solo funciona en macOS."
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 14 )) || fail "$NAME necesita macOS 14 (Sonoma) o posterior. Tienes $(sw_vers -productVersion)."

bold "Descargando ${NAME}…"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fL --progress-bar "$URL" -o "$tmp/${NAME}.zip" || fail "No se pudo descargar $URL"
ditto -x -k "$tmp/${NAME}.zip" "$tmp"
[[ -d "$tmp/${NAME}.app" ]] || fail "El archivo descargado no contiene ${NAME}.app"

# Close a running copy so it can be replaced.
if pgrep -x "$NAME" >/dev/null; then
    bold "Cerrando ${NAME}…"
    osascript -e "quit app \"$NAME\"" 2>/dev/null || true
    sleep 1
    pkill -x "$NAME" 2>/dev/null || true
fi

dest="/Applications"
if [[ ! -w "$dest" ]]; then
    dest="$HOME/Applications"
    mkdir -p "$dest"
fi
rm -rf "$dest/${NAME}.app"
mv "$tmp/${NAME}.app" "$dest/"
# The app is not notarized; skip the Gatekeeper prompt for this copy.
xattr -dr com.apple.quarantine "$dest/${NAME}.app" 2>/dev/null || true
bold "Instalado en $dest/${NAME}.app"

open "$dest/${NAME}.app"
bold "¡Listo!"
