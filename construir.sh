#!/bin/zsh
# Compila Garita y la empaqueta como build/Garita.app (firmada; ver más abajo).
# Uso:  ./construir.sh          → compila y empaqueta (solo para la arquitectura de este Mac)
#       ./construir.sh abrir    → además, lanza la app
#       UNIVERSAL=1 ./construir.sh  → binario universal (Apple Silicon + Intel), lo usa empaquetar.sh
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Garita.app"

# Arquitecturas: por defecto la de este Mac (más rápido para desarrollar).
ARQUITECTURAS=()
MODO="release"
if [[ "${UNIVERSAL:-0}" == "1" ]]; then
    ARQUITECTURAS=(--arch arm64 --arch x86_64)
    MODO="release, universal"
fi

echo "→ Compilando ($MODO)…"
swift build -c release "${ARQUITECTURAS[@]}"

echo "→ Empaquetando $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release "${ARQUITECTURAS[@]}" --show-bin-path)/Garita" "$APP/Contents/MacOS/"
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

# Firma: con el certificado propio si existe (ver crear-certificado.sh), para que
# macOS reconozca siempre a Garita como la misma app y conserve sus permisos.
# Si no existe, firma ad-hoc (funciona, pero los permisos se pierden al recompilar).
CERTIFICADO="Garita (firma local)"
if security find-certificate -c "$CERTIFICADO" >/dev/null 2>&1; then
    echo "→ Firmando con \"$CERTIFICADO\"…"
    codesign --force --sign "$CERTIFICADO" "$APP"
else
    echo "→ Firmando ad-hoc (crea un certificado propio con ./crear-certificado.sh)…"
    codesign --force --sign - "$APP"
fi

echo "✓ Listo: $APP"

if [[ "${1:-}" == "abrir" ]]; then
    pkill -x Garita 2>/dev/null || true
    open "$APP"
fi
