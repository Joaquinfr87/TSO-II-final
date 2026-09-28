#!/bin/bash
set -euo pipefail

# ===================================================================
# deploy.sh — Aplica la configuración de servidor versionada en el repo.
#
# Uso (EN EL SERVIDOR, dentro del repo clonado):
#   git pull
#   sudo bash server/deploy.sh
#
# Aplica config nativa (firewall, ssh, ntp) y luego levanta/actualiza
# los contenedores (docker compose) con su configuración versionada.
# Hace validaciones antes de aplicar para no dejar el server sin acceso.
# ===================================================================

DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$DIR/.." && pwd)"

echo "==> [1/6] Validando sintaxis de nftables.conf ..."
if sudo nft -c -f "$DIR/nftables.conf" 2>/dev/null; then
    echo "    sintaxis OK"
else
    echo "    ERROR: sintaxis inválida en $DIR/nftables.conf"
    echo "    No se aplica NADA para no perder conectividad."
    exit 1
fi

echo "==> [2/6] Aplicando firewall ..."
sudo cp "$DIR/nftables.conf" /etc/nftables.conf
# Borra SOLO nuestra tabla (inet filter) para no arrastrar las cadenas
# internas de Docker. Un "flush ruleset" global rompería el NAT de los
# contenedores (error "No chain/target/match by that name").
sudo nft delete table inet filter 2>/dev/null || true
sudo nft -f /etc/nftables.conf
sudo systemctl enable nftables >/dev/null 2>&1 || true
echo "    firewall activo (tabla inet filter)"

echo "==> [3/6] Respaldo y validación de sshd_config ..."
BACKUP="${BACKUP:-}"
if [ -f /etc/ssh/sshd_config ]; then
    BACKUP="/etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)"
    sudo cp /etc/ssh/sshd_config "$BACKUP"
    echo "    respaldo en $BACKUP"
fi
sudo cp "$DIR/sshd_config" /etc/ssh/sshd_config

echo "==> [4/6] Verificando y reiniciando ssh ..."
if sudo sshd -t; then
    sudo systemctl restart ssh
    echo "    ssh reiniciado correctamente"
else
    echo "    ERROR: sshd -t falló. No se reinicia ssh."
    echo "    Restaurar respaldo:"
    echo "      sudo cp $BACKUP /etc/ssh/sshd_config && sudo systemctl restart ssh"
    exit 1
fi

echo "==> [5/6] Chrony (NTP) ..."
if [ -f /etc/chrony/chrony.conf ]; then
    BACKUP_CHRONY="/etc/chrony/chrony.conf.bak.$(date +%Y%m%d%H%M%S)"
    sudo cp /etc/chrony/chrony.conf "$BACKUP_CHRONY"
    echo "    respaldo en $BACKUP_CHRONY"
fi
sudo cp "$DIR/chrony.conf" /etc/chrony/chrony.conf
sudo systemctl enable --now chrony
sudo systemctl restart chrony
echo "    chrony reiniciado (servidor NTP de la LAN)"

echo "==> [6/6] Contenedores (docker compose) ..."
if [ ! -f "$ROOT/docker-compose.yml" ]; then
    echo "    ERROR: no se encontró $ROOT/docker-compose.yml"
    exit 1
fi
# Valida la configuración de nginx (services/web/nginx.conf) sin tocar nada.
# OJO: montar tls/ (certs) porque el conf declara ssl_certificate; sin esa
# ruta nginx -t falla con "cannot load certificate" aunque el conf es válido.
echo "    validando services/web/nginx.conf ..."
if [ ! -f "$ROOT/services/web/tls/server.crt" ]; then
    echo "    ATENCIÓN: falta services/web/tls/ (certs, no versionado). Correr:"
    echo "      sudo bash $ROOT/services/web/tls-gen.sh"
fi
if sudo docker run --rm \
        -v "$ROOT/services/web/nginx.conf:/etc/nginx/conf.d/default.conf:ro" \
        -v "$ROOT/services/web/tls:/etc/nginx/tls:ro" \
        nginx:1.27-alpine nginx -t >/dev/null 2>&1; then
    echo "    nginx.conf OK"
else
    echo "    ERROR: nginx.conf inválido → NO se tocan los contenedores."
    exit 1
fi
# Valida las configs del stack de monitoreo (services/monitoring).
echo "    validando services/monitoring/ ..."
if sudo docker run --rm --entrypoint promtool \
        -v "$ROOT/services/monitoring/prometheus:/etc/prometheus:ro" \
        "prom/prometheus:${PROMETHEUS_TAG:-v3.15.0}" \
        check config /etc/prometheus/prometheus.yml >/dev/null; then
    echo "    prometheus.yml + reglas OK"
else
    echo "    ERROR: configuración de Prometheus inválida → NO se tocan los contenedores."
    exit 1
fi
if sudo docker run --rm --entrypoint amtool \
        -v "$ROOT/services/monitoring/alertmanager:/etc/alertmanager:ro" \
        "prom/alertmanager:${ALERTMANAGER_TAG:-v0.34.1}" \
        check-config /etc/alertmanager/alertmanager.yml >/dev/null; then
    echo "    alertmanager.yml OK"
else
    echo "    ERROR: configuración de Alertmanager inválida → NO se tocan los contenedores."
    exit 1
fi
if sudo docker run --rm --entrypoint blackbox_exporter \
        -v "$ROOT/services/monitoring/blackbox:/etc/blackbox:ro" \
        "prom/blackbox-exporter:${BLACKBOX_TAG:-v0.28.0}" \
        --config.check --config.file=/etc/blackbox/blackbox.yml >/dev/null; then
    echo "    blackbox.yml OK"
else
    echo "    ERROR: configuración de blackbox inválida → NO se tocan los contenedores."
    exit 1
fi
if [ ! -f "$ROOT/.env" ]; then
    echo "    ATENCIÓN: falta $ROOT/.env (copiar de .env.example) → compose usa defaults."
else
    # El webmail (Roundcube) declara ROUNDCUBE_DES_KEY como obligatoria:
    # sin ella la interpolación de compose aborta TODO el deploy.
    if ! grep -qE '^ROUNDCUBE_DES_KEY=[^[:space:]#]+' "$ROOT/.env"; then
        echo "    ERROR: falta ROUNDCUBE_DES_KEY en $ROOT/.env → docker compose aborta."
        echo "      echo \"ROUNDCUBE_DES_KEY=\$(openssl rand -hex 32)\" >> $ROOT/.env"
        exit 1
    fi
    if grep -qE '^ROUNDCUBE_DES_KEY=CambiarEstaClave' "$ROOT/.env"; then
        echo "    ATENCIÓN: ROUNDCUBE_DES_KEY sigue con el valor de ejemplo del repo."
    fi
    # Sin cuentas de correo no hay nadie que pueda entrar al webmail.
    MAIL_USERS="$(grep -E '^MAIL_USERS=' "$ROOT/.env" | tail -1 | cut -d= -f2- | tr -d "\"'" | xargs)"
    if [ -z "$MAIL_USERS" ]; then
        echo "    ATENCIÓN: MAIL_USERS vacío en $ROOT/.env → el webmail no tendrá cuentas."
        echo "      MAIL_USERS=\"joaquin:Pass1! david:Pass2!\"   (formato user:pass user2:pass2)"
    elif printf '%s' "$MAIL_USERS" | grep -q "CambiarMe"; then
        echo "    ATENCIÓN: MAIL_USERS sigue con las claves de ejemplo del repo (.env.example)."
    fi
    # El gestor de archivos (Filebrowser) declara FILES_ADMIN_PASS obligatoria.
    if ! grep -qE '^FILES_ADMIN_PASS=[^[:space:]#]+' "$ROOT/.env"; then
        echo "    ERROR: falta FILES_ADMIN_PASS en .env → docker compose aborta."
        echo "      echo 'FILES_ADMIN_PASS=Admin2026!' >> $ROOT/.env"
        exit 1
    fi
    if grep -qE '^FILES_ADMIN_PASS=CambiarMeFiles' "$ROOT/.env"; then
        echo "    ATENCIÓN: FILES_ADMIN_PASS sigue con el valor de ejemplo del repo."
    fi
    # Grafana declara GRAFANA_ADMIN_PASSWORD y GF_SECRET_KEY como obligatorias.
    for v in GRAFANA_ADMIN_PASSWORD GF_SECRET_KEY; do
        if ! grep -qE "^${v}=[^[:space:]#]+" "$ROOT/.env"; then
            echo "    ERROR: falta $v en .env → docker compose aborta."
            echo "      echo \"$v=\$(openssl rand -hex 32)\" >> $ROOT/.env"
            exit 1
        fi
        if grep -qE "^${v}=Cambiar" "$ROOT/.env"; then
            echo "    ATENCIÓN: $v sigue con el valor de ejemplo del repo."
        fi
    done
    # gid del grupo dueño de los shares: sin él, los archivos creados desde
    # la web quedan root:root y nadie puede escribirlos por SMB.
    if ! grep -qE '^FILES_GID=[0-9]+' "$ROOT/.env"; then
        FG="$(stat -c %g /srv/samba/departamentos 2>/dev/null || true)"
        if [ -n "$FG" ]; then
            echo "    ATENCIÓN: FILES_GID vacío en .env (gid de los shares = $FG):"
            echo "      echo \"FILES_GID=$FG\" >> $ROOT/.env"
        else
            echo "    ATENCIÓN: FILES_GID vacío y todavía no existe /srv/samba/departamentos."
        fi
    fi
fi
cd "$ROOT"
sudo docker compose up -d --build
echo "    contenedores levantados/actualizados"

echo
echo "===================================================================="
echo "  Deploy completado."
echo "  * Firewall nftables: tabla inet filter aplicada y habilitada"
echo "  * SSH: config endurecida (claves, sin root, solo admins)"
echo "  * Chrony: sirviendo hora a 192.168.0.0/24"
echo "  * Contenedores: docker compose up -d --build (proxy web actualizado)"
echo "  * DNS: si hay nombres nuevos (david/nicolas), agregar los A hacia"
echo "    192.168.0.2 (ver docs/publicar-servicios-admin.md y dc/dns-records.sh)"
echo "  * Probar en OTRA terminal: ssh joaquin@192.168.0.2"
echo
echo "  Si los contenedores pierden red tras aplicar el firewall,"
echo "  reiniciar Docker (recrea sus cadenas):"
echo "    sudo systemctl restart docker"
echo "===================================================================="