#!/bin/zsh
# Prepara el ClamAV que va DENTRO de Garita.app, a partir del instalador oficial
# de Cisco para macOS (universal: Apple Silicon + Intel).
#
# Resultado en vendor/clamav-integrado/ (construir.sh lo copia a la app):
#   Helpers/     clamscan, freshclam           → Garita.app/Contents/Helpers/
#   Frameworks/  libclamav y compañía (.dylib) → Garita.app/Contents/Frameworks/
#   Resources/   certificado de firmas, licencias y origen del código
#                                              → Garita.app/Contents/Resources/clamav/
#
# Los programas de Cisco buscan sus librerías en /usr/local/clamav/lib; aquí se
# cambia para que las busquen dentro de la app (@executable_path/../Frameworks).
# Al modificarlos se pierde la firma de Cisco, así que construir.sh los vuelve a
# firmar con la de Garita.
#
# Uso:  ./preparar-clamav.sh            (versión por defecto)
#       ./preparar-clamav.sh 1.5.5      (otra versión)
set -euo pipefail
cd "$(dirname "$0")"

VERSION="${1:-1.5.4}"
PAQUETE="clamav-$VERSION.macos.universal.pkg"
URL="https://github.com/Cisco-Talos/clamav/releases/download/clamav-$VERSION/$PAQUETE"
TRABAJO="vendor"
DESTINO="$TRABAJO/clamav-integrado"
mkdir -p "$TRABAJO"

# 1. Descargar el instalador oficial (si no está ya) y comprobar que lo firma Cisco.
if [[ ! -f "$TRABAJO/$PAQUETE" ]]; then
    echo "→ Descargando $PAQUETE…"
    curl -fL --progress-bar -o "$TRABAJO/$PAQUETE" "$URL"
fi
echo "→ Comprobando la firma del paquete…"
if ! pkgutil --check-signature "$TRABAJO/$PAQUETE" | grep -q "Developer ID Installer: Cisco"; then
    echo "✗ El paquete no está firmado por Cisco. No lo uso." >&2
    exit 1
fi

# 2. Abrirlo (sin instalar nada en el sistema).
echo "→ Extrayendo…"
rm -rf "$TRABAJO/pkg"
pkgutil --expand-full "$TRABAJO/$PAQUETE" "$TRABAJO/pkg"
PROGRAMAS="$TRABAJO/pkg/clamav-$VERSION.macos.universal-programs.pkg/Payload/usr/local/clamav"
LIBRERIAS="$TRABAJO/pkg/clamav-$VERSION.macos.universal-libraries.pkg/Payload/usr/local/clamav/lib"

# 3. Copiar solo lo necesario. Las librerías se copian con el nombre con el que
#    las piden los programas (p. ej. libclamav.12.dylib), sin enlaces simbólicos.
rm -rf "$DESTINO"
mkdir -p "$DESTINO/Helpers" "$DESTINO/Frameworks" "$DESTINO/Resources/certs" "$DESTINO/Resources/licencias"
cp "$PROGRAMAS/bin/clamscan" "$PROGRAMAS/bin/freshclam" "$DESTINO/Helpers/"
for nombre in libclamav.12 libclammspack.0 libfreshclam.4 libclamunrar.12 libclamunrar_iface.12; do
    cp -L "$LIBRERIAS/$nombre.dylib" "$DESTINO/Frameworks/$nombre.dylib"
done
cp "$PROGRAMAS/etc/certs/"* "$DESTINO/Resources/certs/"

# 4. Que busquen sus librerías dentro de la app, y no en /usr/local/clamav.
echo "→ Reubicando las librerías dentro de la app…"
for binario in "$DESTINO"/Helpers/* "$DESTINO"/Frameworks/*; do
    chmod u+w "$binario"
    install_name_tool -delete_rpath /usr/local/clamav/lib "$binario" 2>/dev/null || true
done
for programa in "$DESTINO"/Helpers/*; do
    install_name_tool -add_rpath @executable_path/../Frameworks "$programa" 2>/dev/null
done
for libreria in "$DESTINO"/Frameworks/*; do
    install_name_tool -add_rpath @loader_path "$libreria" 2>/dev/null
done

# 5. Licencias (ClamAV es GPLv2: hay que incluirlas e indicar dónde está el código).
cp "$TRABAJO/pkg/Resources/License.txt" "$DESTINO/Resources/licencias/ClamAV-License.txt"
find "$TRABAJO/pkg" -iname "COPYING*" -type f -exec cp {} "$DESTINO/Resources/licencias/" \; 2>/dev/null || true
cat > "$DESTINO/Resources/licencias/LEEME.txt" <<EOF
Garita incluye ClamAV $VERSION (https://www.clamav.net), de Cisco Systems, Inc.

ClamAV es software libre bajo la licencia GNU GPL versión 2 (ver
ClamAV-License.txt). Garita lo ejecuta como programa independiente
(clamscan, freshclam); no enlaza su librería.

Código fuente de esta versión de ClamAV:
  https://github.com/Cisco-Talos/clamav/releases/tag/clamav-$VERSION

Los binarios proceden del instalador oficial $PAQUETE; el único cambio es
la ruta de búsqueda de sus librerías (para que funcionen dentro de la app)
y la firma de código. ClamAV es una marca de Cisco Systems, Inc.
EOF
echo "$VERSION" > "$DESTINO/Resources/VERSION"

echo "✓ ClamAV $VERSION preparado en $DESTINO ($(du -sh "$DESTINO" | cut -f1))"
