#!/usr/bin/env bash
# =====================================================================
# Instala zabbix-agent2 NATIVO (checks pasivos por :10050)
#
#   En dc1   (192.168.0.2):  sudo bash services/zabbix/install-agent.sh dc1
#   En zabbix(192.168.0.3):  sudo bash services/zabbix/install-agent.sh zabbix
#
# - Repo oficial Zabbix 7.0 (la misma versión del server).
# - Plugin Docker incluido en agent2; requiere el usuario zabbix en el
#   grupo docker (socket /var/run/docker.sock).
# - Server/ServerActive apuntan al server Zabbix:
#     dc1    -> 192.168.0.3 (passivo) y 192.168.0.3:10051 (activo)
#     zabbix -> localhost (el server corre en contenedor: fuente 127.0.0.1
#               y rango bridge docker 172.16.0.0/12)
#
# Post-requisito en dc1: abrir 10050 desde 192.168.0.3 en
# server/nftables.conf (ya incluido) y recargar con server/deploy.sh.
# =====================================================================
set -euo pipefail

ROL="${1:-}"
ZBX_VER="7.0"
SRV="192.168.0.3"
CONF="/etc/zabbix/zabbix_agent2.conf"

case "$ROL" in
    dc1)
        AGENT_HOST="dc1"
        SERVER="${SRV}"
        SERVER_ACTIVE="${SRV}:10051"
        ;;
    zabbix)
        AGENT_HOST="Zabbix server"
        SERVER="127.0.0.1,::1,172.16.0.0/12,192.168.0.0/24"
        SERVER_ACTIVE="127.0.0.1:10051"
        ;;
    *)
        echo "Uso: $0 <dc1|zabbix>" >&2
        exit 1
        ;;
esac

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: ejecutar como root (sudo)." >&2
    exit 1
fi

. /etc/os-release
CODENAME="${VERSION_CODENAME:?}"
echo "==> ${PRETTY_NAME} (${CODENAME}) — rol: ${ROL}"

# ── 1. Repo oficial (idempotente) ───────────────────────────────────
if ! dpkg -s zabbix-release >/dev/null 2>&1; then
    echo "==> Repo oficial Zabbix ${ZBX_VER}"
    DEB="zabbix-release_latest_${ZBX_VER}+${CODENAME}_all.deb"
    curl -fsSL -o "/tmp/${DEB}" \
        "https://repo.zabbix.com/zabbix/${ZBX_VER}/debian/pool/main/z/zabbix-release/${DEB}"
    dpkg -i "/tmp/${DEB}"
    rm -f "/tmp/${DEB}"
fi

echo "==> Instalando zabbix-agent2"
apt-get update -y
apt-get install -y zabbix-agent2

# ── 2. Config ───────────────────────────────────────────────────────
echo "==> Configurando ${CONF}"
cp -a "${CONF}" "${CONF}.bak.$(date +%Y%m%d%H%M%S)"

set_opt() {   # set_opt CLAVE VALOR
    local k="$1" v="$2"
    if grep -qE "^[# ]*${k}=" "${CONF}"; then
        sed -i -E "s|^[# ]*${k}=.*|${k}=${v}|" "${CONF}"
    else
        printf '%s=%s\n' "${k}" "${v}" >> "${CONF}"
    fi
}

set_opt Hostname      "${AGENT_HOST}"
set_opt Server        "${SERVER}"
set_opt ServerActive  "${SERVER_ACTIVE}"
set_opt ListenPort    10050
set_opt Timeout       10

# ── 3. Docker: usuario zabbix sobre el socket ───────────────────────
if getent group docker >/dev/null 2>&1; then
    usermod -aG docker zabbix
    echo "==> usuario 'zabbix' agregado al grupo 'docker'"
else
    echo "AVISO: no existe el grupo 'docker' — el plugin Docker no va a poder leer el socket"
fi

# ── 4. Servicio ─────────────────────────────────────────────────────
systemctl enable --now zabbix-agent2 >/dev/null 2>&1
systemctl restart zabbix-agent2
sleep 1
if systemctl is-active --quiet zabbix-agent2; then
    echo "==> zabbix-agent2 activo"
else
    systemctl status zabbix-agent2 --no-pager -l
    exit 1
fi

echo "==> Escuchando:"
ss -lntp | grep 10050 || { echo "AVISO: no veo el puerto 10050"; exit 1; }

echo
echo "Listo. Verificar desde el server Zabbix (192.168.0.3):"
echo "  nc -vz 192.168.0.2 10050        # solo dc1"
echo "  zabbix_get -s 192.168.0.2 -k docker.info"
