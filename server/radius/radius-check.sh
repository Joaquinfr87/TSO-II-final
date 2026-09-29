#!/bin/bash
set -euo pipefail
# ============================================================
# radius-check.sh — sonda de vida de FreeRADIUS para Prometheus
#
# Manda un Access-Request (PAP) a localhost:1812 y anota si el
# servidor respondió (un Access-Reject también cuenta: está vivo;
# "No reply" = caído). Escribe:
#   /var/lib/tso-backup/radius.prom
# que lee tso-node-exporter (--collector.textfile.directory).
# La alerta RadiusNoResponde sale de tso_radius_up.
#
# Lo instala/cronifica server/deploy.sh en /etc/cron.d/tso-radius.
# ============================================================

STATE_DIR="${STATE_DIR:-/var/lib/tso-backup}"
LOCAL_SECRET="${LOCAL_SECRET:-testing123}"
PROM="$STATE_DIR/radius.prom"

up=0
if command -v radclient >/dev/null 2>&1; then
    out="$(printf 'User-Name = "sonda"\nUser-Password = "nunca-valida"\n' \
        | radclient -r 1 -t 3 127.0.0.1:1812 auth "$LOCAL_SECRET" 2>&1)" || true
    # Hubo respuesta salvo que radclient se queje de timeout/conexión.
    if ! printf '%s' "$out" | grep -qiE 'no reply|timed out|connection refused|failed|error'; then
        up=1
    fi
fi

mkdir -p "$STATE_DIR"
tmp="$PROM.$$"
{
    echo "# HELP tso_radius_up Estado de FreeRADIUS en dc1 (1 = responde, 0 = no responde)."
    echo "# TYPE tso_radius_up gauge"
    echo "tso_radius_up $up"
    echo "# HELP tso_radius_check_timestamp_seconds Momento Unix de la última sonda RADIUS."
    echo "# TYPE tso_radius_check_timestamp_seconds gauge"
    echo "tso_radius_check_timestamp_seconds $(date +%s)"
} >"$tmp" 2>/dev/null || { rm -f "$tmp"; exit 0; }
chmod 644 "$tmp" 2>/dev/null || true
mv -f "$tmp" "$PROM" 2>/dev/null || rm -f "$tmp"
exit 0
