#!/bin/zsh
# Publica una versión de Garita en GitHub Releases, lista para Sparkle.
#
# Uso:  ./publicar.sh            → prepara todo y, tras confirmar, publica
#       ./publicar.sh preparar   → solo prepara (no sube nada), para revisar
#
# Antes de publicar:
#   1. Sube CFBundleShortVersionString y CFBundleVersion en Recursos/Info.plist.
#   2. Escribe las notas de la versión en notas/<versión>.md.
#   3. Haz commit de todo (el árbol tiene que estar limpio).
#
# Qué publica (en la Release v<versión>):
#   - Garita-<versión>.dmg  → para instalar a mano.
#   - Garita-<versión>.zip  → la actualización que descarga Sparkle.
#   - appcast.xml           → la "ficha" que lee Garita cada día, en
#     https://github.com/jaca101/garita/releases/latest/download/appcast.xml
#     (SUFeedURL en Info.plist). Va firmada con la clave EdDSA privada del
#     llavero; Garita la comprueba con SUPublicEDKey antes de instalar.
set -euo pipefail
cd "$(dirname "$0")"

REPO="jaca101/garita"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Recursos/Info.plist)
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" Recursos/Info.plist)
ETIQUETA="v$VERSION"
NOTAS="notas/$VERSION.md"
SALIDA="build/publicar/$VERSION"
SPARKLE_BIN=".build/artifacts/sparkle/Sparkle/bin"

echo "== Publicar Garita $VERSION (build $BUILD) =="

# --- Comprobaciones: mejor fallar aquí que con una Release a medias ---------
[[ -f "$NOTAS" ]] || { echo "✗ Faltan las notas: $NOTAS"; exit 1; }
if [[ "${1:-}" != "preparar" ]]; then
    [[ -z "$(git status --porcelain)" ]] || { echo "✗ Hay cambios sin commit."; git status --short; exit 1; }
    [[ "$(git branch --show-current)" == "main" ]] || { echo "✗ No estás en la rama main."; exit 1; }
fi
if git rev-parse -q --verify "refs/tags/$ETIQUETA" >/dev/null || gh release view "$ETIQUETA" -R "$REPO" >/dev/null 2>&1; then
    echo "✗ La versión $VERSION ya está publicada (o etiquetada). Sube la versión en Info.plist."
    exit 1
fi
[[ -x "$SPARKLE_BIN/generate_appcast" ]] || swift package resolve

# --- Preparar: .dmg universal, .zip y appcast firmado -------------------------
./empaquetar.sh     # compila universal (arm64 + x86_64) y crea build/Garita-<versión>.dmg

echo "→ Preparando la actualización en $SALIDA…"
rm -rf "$SALIDA" && mkdir -p "$SALIDA"
cp "build/Garita-$VERSION.dmg" "$SALIDA/"
# Sparkle descarga el .zip; ditto conserva los enlaces y la firma de la app.
ditto -c -k --sequesterRsrc --keepParent build/Garita.app "$SALIDA/Garita-$VERSION.zip"

echo "→ Generando appcast.xml (firma EdDSA con la clave del llavero)…"
# Solo el .zip en la carpeta de trabajo: el appcast lleva únicamente esta versión,
# que es lo que necesita Sparkle (compara con la instalada).
APPCAST_TMP="$SALIDA/appcast"
mkdir -p "$APPCAST_TMP"
cp "$SALIDA/Garita-$VERSION.zip" "$APPCAST_TMP/"
"$SPARKLE_BIN/generate_appcast" \
    --download-url-prefix "https://github.com/$REPO/releases/download/$ETIQUETA/" \
    --full-release-notes-url "https://github.com/$REPO/releases/tag/$ETIQUETA" \
    --link "https://github.com/$REPO" \
    "$APPCAST_TMP"
mv "$APPCAST_TMP/appcast.xml" "$SALIDA/appcast.xml"
rm -rf "$APPCAST_TMP"

# Comprobaciones de la firma, para no publicar algo que Garita rechazaría:
#   1. la clave del llavero es la misma cuya parte pública lleva Garita (SUPublicEDKey);
#   2. la firma del appcast es válida para el .zip con esa clave.
CLAVE_APP=$(/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" Recursos/Info.plist)
CLAVE_LLAVERO=$("$SPARKLE_BIN/generate_keys" -p)
[[ "$CLAVE_APP" == "$CLAVE_LLAVERO" ]] \
    || { echo "✗ La clave del llavero no es la de Info.plist (SUPublicEDKey)."; exit 1; }
FIRMA=$(sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p' "$SALIDA/appcast.xml")
[[ -n "$FIRMA" ]] || { echo "✗ El appcast no lleva firma EdDSA."; exit 1; }
"$SPARKLE_BIN/sign_update" --verify "$SALIDA/Garita-$VERSION.zip" "$FIRMA" \
    || { echo "✗ La firma del .zip no es válida."; exit 1; }
echo "✓ Firma EdDSA verificada con la clave de Garita."

echo
echo "Preparado en $SALIDA:"
ls -lh "$SALIDA" | tail -n +2

if [[ "${1:-}" == "preparar" ]]; then
    echo "(Solo preparar: no se ha publicado nada.)"
    exit 0
fi

# --- Publicar -----------------------------------------------------------------
echo
read "RESPUESTA?¿Publicar Garita $VERSION en https://github.com/$REPO/releases? (s/N) "
[[ "$RESPUESTA" == [sS] ]] || { echo "Cancelado: no se ha publicado nada."; exit 0; }

echo "→ Subiendo main y la etiqueta $ETIQUETA…"
git push origin main
git tag -a "$ETIQUETA" -m "Garita $VERSION"
git push origin "$ETIQUETA"

echo "→ Creando la Release…"
gh release create "$ETIQUETA" -R "$REPO" \
    --title "Garita $VERSION" \
    --notes-file "$NOTAS" \
    "$SALIDA/Garita-$VERSION.dmg" \
    "$SALIDA/Garita-$VERSION.zip" \
    "$SALIDA/appcast.xml"

echo "✓ Publicada: https://github.com/$REPO/releases/tag/$ETIQUETA"
