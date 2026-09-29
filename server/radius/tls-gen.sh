#!/bin/bash
set -euo pipefail
# ============================================================
# tls-gen.sh — CA interna + certificado del servidor RADIUS (EAP/PEAP)
#
# Genera (NO versionado) en los dirs que use la config de EAP:
#   <cadir>/ca.pem      ← CA "SUDOERS.LAN RADIUS CA" (importar en clientes)
#   <cadir>/ca.der      ← la misma CA en DER (para Windows: doble clic)
#   <certdir>/server.pem ← clave + cert del servidor RADIUS
#                          (CN=radius.sudoers.lan, SAN dc1/radius/IP)
#
# Uso (EN EL SERVIDOR):
#   sudo bash server/radius/tls-gen.sh
#   server/deploy.sh lo corre solo si faltan los certs.
#
# Los clientes confían en el cert instalando ca.pem/ca.der como
# "Autoridad de certificación raíz de confianza".
# ============================================================

RADD="${RADD:-/etc/freeradius/3.0}"
DOMAIN="${DOMAIN:-sudoers.lan}"
DC_HOST="${DC_HOST:-dc1}"
IP="${IP:-192.168.0.2}"
DAYS_CA="${DAYS_CA:-3650}"
DAYS_SERVER="${DAYS_SERVER:-825}"

# ── Dir de certs: leer certdir/cadir de radiusd.conf si existe ──
conf="$RADD/radiusd.conf"
certdir=""
cadir=""
if [ -f "$conf" ]; then
    certdir="$(awk '$1=="certdir" {sub(/^[^=]*=[ \t]*/,""); sub(/[ \t]+$/,""); print; exit}' "$conf")"
    cadir="$(awk '$1=="cadir" {sub(/^[^=]*=[ \t]*/,""); sub(/[ \t]+$/,""); print; exit}' "$conf")"
fi
# expandir ${confdir} (constante aparte: ${...} anidado rompe el parseo)
# shellcheck disable=SC2016  # se quiere el texto literal, sin expandir
CONST_CONFDIR='${confdir}'
certdir="${certdir:-$CONST_CONFDIR/certs}"
cadir="${cadir:-$CONST_CONFDIR/certs}"
certdir="${certdir//\$\{confdir\}/$RADD}"
cadir="${cadir//\$\{confdir\}/$RADD}"
# shellcheck disable=SC2016  # patrón literal, sin expandir
case "$certdir$cadir" in
    *'${'*)
        echo "ERROR: no pude resolver certdir/cadir de $conf (valor: $certdir / $cadir)" >&2
        exit 1
        ;;
esac
mkdir -p "$certdir" "$cadir"

# ── CA interna (se genera una sola vez) ─────────────────────
if [ ! -s "$cadir/ca.pem" ]; then
    echo "=> Generando CA RADIUS ..."
    openssl genrsa -out "$cadir/ca.key" 4096
    openssl req -new -x509 -days "$DAYS_CA" -key "$cadir/ca.key" -sha256 \
        -subj "/C=AR/O=SUDOERS.LAN/CN=SUDOERS.LAN RADIUS CA" \
        -out "$cadir/ca.pem"
    openssl x509 -in "$cadir/ca.pem" -outform DER -out "$cadir/ca.der"
    chmod 600 "$cadir/ca.key"
    chmod 644 "$cadir/ca.pem" "$cadir/ca.der"
else
    echo "=> CA existente, se reutiliza ($cadir/ca.pem)."
    [ -s "$cadir/ca.der" ] || openssl x509 -in "$cadir/ca.pem" -outform DER -out "$cadir/ca.der"
fi

# ── Cert del servidor RADIUS (key + cert en server.pem) ─────
echo "=> Generando cert del servidor RADIUS ..."
openssl req -newkey rsa:2048 -nodes \
    -keyout "$certdir/server.key" -sha256 \
    -subj "/C=AR/O=SUDOERS.LAN/CN=radius.$DOMAIN" \
    -addext "basicConstraints=CA:FALSE" \
    -addext "keyUsage=digitalSignature,keyEncipherment" \
    -addext "extendedKeyUsage=serverAuth" \
    -addext "subjectAltName=DNS:radius.$DOMAIN,DNS:$DC_HOST.$DOMAIN,DNS:$DOMAIN,IP:$IP" \
    -out "$certdir/server.csr"

openssl x509 -req \
    -in "$certdir/server.csr" \
    -CA "$cadir/ca.pem" -CAkey "$cadir/ca.key" -CAcreateserial \
    -days "$DAYS_SERVER" -sha256 \
    -copy_extensions copy \
    -out "$certdir/server.crt"

# EAP usa private_key_file = certificate_file = server.pem (clave+cert juntos)
cat "$certdir/server.key" "$certdir/server.crt" > "$certdir/server.pem"
rm -f "$certdir/server.csr"
chmod 600 "$certdir/server.key" "$certdir/server.pem"
chmod 644 "$certdir/server.crt"

echo "============================================"
echo "  TLS de RADIUS listo"
echo "  CA (importar en clientes): $cadir/ca.pem  (también ca.der)"
echo "  Server:                    $certdir/server.pem"
echo "  Vida: CA ${DAYS_CA}d / server ${DAYS_SERVER}d"
echo "  Deploy: sudo bash server/deploy.sh"
echo "============================================"
