#!/bin/zsh
# Compila Garita y la empaqueta como build/Garita.app (firma ad-hoc).
# Uso:  ./construir.sh          → compila y empaqueta
#       ./construir.sh abrir    → además, lanza la app
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Garita.app"

echo "→ Compilando (release)…"
swift build -c release

echo "→ Empaquetando $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Garita" "$APP/Contents/MacOS/"
cp Recursos/Info.plist "$APP/Contents/"

echo "→ Firmando ad-hoc…"
codesign --force --sign - "$APP"

echo "✓ Listo: $APP"

if [[ "${1:-}" == "abrir" ]]; then
    pkill -x Garita 2>/dev/null || true
    open "$APP"
fi
