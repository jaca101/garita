#!/bin/zsh
# Compila Garita y la instala (o actualiza) en /Applications, y la abre.
#
# - Sustituye /Applications/Garita.app por la versión recién compilada.
# - Quita del registro de apps la copia de build/, para que el Finder no muestre
#   dos "Escanear con Garita" ni abra la copia equivocada.
# - Los permisos (Acceso total al disco…) se conservan porque la firma es la
#   misma (certificado "Garita (firma local)", ver crear-certificado.sh).
#
# Uso:  ./instalar.sh
set -euo pipefail
cd "$(dirname "$0")"

LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

./construir.sh

echo "→ Cerrando Garita si está abierta…"
pkill -x Garita 2>/dev/null || true
# Y cualquier escaneo que hubiera lanzado (reconocible por sus opciones de límite),
# para que no se quede trabajando sin nadie que recoja el resultado.
pkill -f "clamscan -r --max-filesize=2000M" 2>/dev/null || true
sleep 1

echo "→ Instalando en /Applications/Garita.app…"
rm -rf /Applications/Garita.app
ditto build/Garita.app /Applications/Garita.app

"$LSREGISTER" -u build/Garita.app 2>/dev/null || true
"$LSREGISTER" -f /Applications/Garita.app

echo "→ Abriendo Garita…"
open /Applications/Garita.app
echo "✓ Garita instalada en /Applications"
