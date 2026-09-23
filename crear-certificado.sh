#!/bin/zsh
# Crea un certificado propio para firmar Garita: "Garita (firma local)".
#
# ¿Para qué? macOS asocia los permisos (Acceso total al disco, Descargas…) a la
# firma de la app. Con la firma ad-hoc, cada compilación es "otra app" y los
# permisos se pierden. Con este certificado la firma es siempre la misma, así
# que los permisos se conservan entre compilaciones y actualizaciones.
#
# No sustituye a una cuenta de Apple Developer: en otros Macs Gatekeeper seguirá
# avisando la primera vez (el certificado solo existe en este llavero).
#
# Qué hace:
#   1. Genera una clave y un certificado autofirmado (10 años, solo para firmar código).
#   2. Los importa en tu llavero de inicio de sesión, permitiendo que codesign use la clave.
#   3. Borra los archivos temporales (la clave queda solo en el llavero).
#
# Para quitarlo: Acceso a Llaveros → inicio de sesión → Mis certificados →
# "Garita (firma local)" → eliminar.
set -euo pipefail

NOMBRE="Garita (firma local)"
LLAVERO="$HOME/Library/Keychains/login.keychain-db"

if security find-certificate -c "$NOMBRE" "$LLAVERO" >/dev/null 2>&1; then
    echo "✓ El certificado \"$NOMBRE\" ya existe en tu llavero. Nada que hacer."
    exit 0
fi

TEMPORAL=$(mktemp -d)
trap 'rm -rf "$TEMPORAL"' EXIT

echo "→ Generando clave y certificado…"
cat > "$TEMPORAL/config.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NOMBRE
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -config "$TEMPORAL/config.cnf" \
    -keyout "$TEMPORAL/clave.pem" -out "$TEMPORAL/certificado.pem" 2>/dev/null

# El llavero importa clave + certificado juntos en formato .p12 (con una contraseña
# temporal que solo se usa en este paso).
/usr/bin/openssl pkcs12 -export -passout pass:temporal \
    -inkey "$TEMPORAL/clave.pem" -in "$TEMPORAL/certificado.pem" \
    -out "$TEMPORAL/garita.p12"

echo "→ Importándolo en el llavero de inicio de sesión…"
# -T /usr/bin/codesign: codesign puede usar la clave sin preguntar cada vez.
security import "$TEMPORAL/garita.p12" -k "$LLAVERO" -P temporal -T /usr/bin/codesign >/dev/null

echo "✓ Certificado \"$NOMBRE\" creado. construir.sh lo usará automáticamente."
