#!/bin/bash
set -euo pipefail

# ===================================================================
# deploy.sh — Aplica la configuración de servidor versionada en el repo.
#
# Uso (EN EL SERVIDOR, dentro del repo clonado):
#   git pull
#   sudo bash server/deploy.sh
#
# Hace validaciones antes de aplicar para no dejar el server sin acceso.
# ===================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"

echo "==> [1/5] Validando sintaxis de nftables.conf ..."
if sudo nft -c -f "$DIR/nftables.conf" 2>/dev/null; then
    echo "    sintaxis OK"
else
    echo "    ERROR: sintaxis inválida en $DIR/nftables.conf"
    echo "    No se aplica NADA para no perder conectividad."
    exit 1
fi

echo "==> [2/5] Aplicando firewall ..."
sudo cp "$DIR/nftables.conf" /etc/nftables.conf
# Borra SOLO nuestra tabla (inet filter) para no arrastrar las cadenas
# internas de Docker. Un "flush ruleset" global rompería el NAT de los
# contenedores (error "No chain/target/match by that name").
sudo nft delete table inet filter 2>/dev/null || true
sudo nft -f /etc/nftables.conf
sudo systemctl enable nftables >/dev/null 2>&1 || true
echo "    firewall activo (tabla inet filter)"

echo "==> [3/5] Respaldo y validación de sshd_config ..."
BACKUP="${BACKUP:-}"
if [ -f /etc/ssh/sshd_config ]; then
    BACKUP="/etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)"
    sudo cp /etc/ssh/sshd_config "$BACKUP"
    echo "    respaldo en $BACKUP"
fi
sudo cp "$DIR/sshd_config" /etc/ssh/sshd_config

echo "==> [4/5] Verificando y reiniciando ssh ..."
if sudo sshd -t; then
    sudo systemctl restart ssh
    echo "    ssh reiniciado correctamente"
else
    echo "    ERROR: sshd -t falló. No se reinicia ssh."
    echo "    Restaurar respaldo:"
    echo "      sudo cp $BACKUP /etc/ssh/sshd_config && sudo systemctl restart ssh"
    exit 1
fi

echo "==> [5/5] Chrony (NTP) ..."
if [ -f /etc/chrony/chrony.conf ]; then
    BACKUP_CHRONY="/etc/chrony/chrony.conf.bak.$(date +%Y%m%d%H%M%S)"
    sudo cp /etc/chrony/chrony.conf "$BACKUP_CHRONY"
    echo "    respaldo en $BACKUP_CHRONY"
fi
sudo cp "$DIR/chrony.conf" /etc/chrony/chrony.conf
sudo systemctl enable --now chrony
sudo systemctl restart chrony
echo "    chrony reiniciado (servidor NTP de la LAN)"

echo
echo "===================================================================="
echo "  Deploy completado."
echo "  * Firewall nftables: tabla inet filter aplicada y habilitada"
echo "  * SSH: config endurecida (claves, sin root, solo admins)"
echo "  * Chrony: sirviendo hora a 192.168.0.0/24"
echo "  * Probar en OTRA terminal: ssh joaquin@192.168.0.2"
echo
echo "  Si los contenedores pierden red tras aplicar el firewall,"
echo "  reiniciar Docker (recrea sus cadenas):"
echo "    sudo systemctl restart docker"
echo "===================================================================="