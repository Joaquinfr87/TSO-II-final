#!/bin/bash
set -e

# ========================================
# Entrypoint para Kea DHCP
# Reemplaza los tokens de kea-dhcp4.conf
# con las variables del .env
# ========================================

SUB="${DHCP_SUBNET:-192.168.0.0/24}"
POOL="${DHCP_POOL:-192.168.0.100 - 192.168.0.199}"
DNS_SRV="${DHCP_DNS:-192.168.0.2}"
DOMAIN="${DNS_DOMAIN:-sudoers.lan}"
GATEWAY="${DHCP_GATEWAY:-192.168.0.1}"
NTP_SRV="${DHCP_NTP:-192.168.0.2}"

CONF="/etc/kea/kea-dhcp4.conf"

# Directorios de runtime y de concesiones (Kea corre como usuario _kea)
mkdir -p /run/kea /var/lib/kea
chown -R _kea:_kea /run/kea /var/lib/kea

# ── Reservas DHCP por MAC ────────────────────────────────────────────
# Formato en .env (separadas por ';'):  MAC=IP=hostname
#   DHCP_RESERVATIONS="aa:bb:cc:dd:ee:ff=192.168.0.50=pc-joaquin;..."
# Rango reservado para equipos fijos: .50–.99 (plan de red).
# ---------------------------------------------------------------------
RESERVATIONS="[]"
if [ -n "${DHCP_RESERVATIONS:-}" ]; then
    RESERVATIONS="["
    FIRST=1
    IFS=';' read -ra ENTRIES <<< "${DHCP_RESERVATIONS}"
    for entry in "${ENTRIES[@]}"; do
        MAC="${entry%%=*}"
        REST="${entry#*=}"
        IP="${REST}"
        HOST=""
        if [[ "${REST}" == *"="* ]]; then
            IP="${REST%%=*}"
            HOST="${REST#*=}"
        fi
        [ -z "${MAC}" ] && continue
        if [ ${FIRST} -eq 1 ]; then FIRST=0; else RESERVATIONS+=","; fi
        RESERVATIONS+="{\"hw-address\":\"${MAC}\",\"ip-address\":\"${IP}\""
        [ -n "${HOST}" ] && RESERVATIONS+=",\"hostname\":\"${HOST}\""
        RESERVATIONS+="}"
    done
    RESERVATIONS+="]"
fi

# Reemplazar tokens de la plantilla
sed -i \
    -e "s|__DHCP_SUBNET__|${SUB}|g" \
    -e "s|__DHCP_POOL__|${POOL}|g" \
    -e "s|__DHCP_DNS__|${DNS_SRV}|g" \
    -e "s|__DNS_DOMAIN__|${DOMAIN}|g" \
    -e "s|__DHCP_GATEWAY__|${GATEWAY}|g" \
    -e "s|__DHCP_NTP__|${NTP_SRV}|g" \
    -e "s|__DHCP_RESERVATIONS__|${RESERVATIONS}|g" \
    "${CONF}"

echo "============================================"
echo "  DHCP Kea"
echo "  Subred:   ${SUB}"
echo "  Pool:     ${POOL}"
echo "  DNS:      ${DNS_SRV}"
echo "  Dominio:  ${DOMAIN}"
echo "  Gateway:  ${GATEWAY}"
echo "  NTP:      ${NTP_SRV}"
echo "  Reservas: ${RESERVATIONS}"
echo "============================================"

exec /usr/sbin/kea-dhcp4 -c "${CONF}"