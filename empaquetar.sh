#!/bin/zsh
# Genera build/Garita-<versión>.dmg para instalar Garita en otros Macs.
#
# El .dmg contiene:
#   Garita.app      binario universal (Apple Silicon + Intel), firmado con el certificado propio (o ad-hoc)
#   Aplicaciones    acceso directo a /Applications, para arrastrar la app
#   LEEME.txt       pasos de la primera vez (Gatekeeper, ClamAV, permisos)
#
# Uso:  ./empaquetar.sh
set -euo pipefail
cd "$(dirname "$0")"

# La versión sale de Info.plist (CFBundleShortVersionString).
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Recursos/Info.plist)
DMG="build/Garita-$VERSION.dmg"

echo "== Garita $VERSION =="
UNIVERSAL=1 ./construir.sh

echo "→ Preparando el contenido del disco…"
CONTENIDO="build/dmg"
rm -rf "$CONTENIDO" && mkdir -p "$CONTENIDO"
cp -R build/Garita.app "$CONTENIDO/"
ln -s /Applications "$CONTENIDO/Aplicaciones"
cp Recursos/LEEME.txt "$CONTENIDO/"

echo "→ Creando $DMG…"
rm -f "$DMG"
# UDZO = imagen comprimida de solo lectura, el formato habitual para distribuir.
hdiutil create -volname "Garita $VERSION" -srcfolder "$CONTENIDO" -ov -format UDZO "$DMG" >/dev/null

echo "✓ Listo: $DMG ($(du -h "$DMG" | cut -f1))"
