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

echo "→ Generando el icono desde Recursos/Icono-1024.png…"
# macOS pide cada tamaño en normal y @2x; sips los reescala e iconutil los junta en un .icns.
ICONOS="build/Garita.iconset"
rm -rf "$ICONOS" && mkdir -p "$ICONOS"
for lado in 16 32 128 256 512; do
    sips -z $lado $lado           Recursos/Icono-1024.png --out "$ICONOS/icon_${lado}x${lado}.png"    >/dev/null
    sips -z $((lado*2)) $((lado*2)) Recursos/Icono-1024.png --out "$ICONOS/icon_${lado}x${lado}@2x.png" >/dev/null
done
iconutil -c icns "$ICONOS" -o "$APP/Contents/Resources/Garita.icns"

echo "→ Firmando ad-hoc…"
codesign --force --sign - "$APP"

echo "✓ Listo: $APP"

if [[ "${1:-}" == "abrir" ]]; then
    pkill -x Garita 2>/dev/null || true
    open "$APP"
fi
