#!/bin/bash
set -euo pipefail

# ===================================================================
# dc/dns-records.sh — Registros A de servicios públicos (idempotente).
#
# Crea/verifica en el DNS AD los nombres que publican servicios web.
# Todos apuntan SIEMPRE al proxy (192.168.0.2), NUNCA a la máquina.
#
# Uso (EN EL DC, con ticket Kerberos de administrador):
#   sudo kinit administrator        # pide el password una sola vez
#   sudo bash dc/dns-records.sh
#
# Guía de publicación: docs/publicar-servicios-admin.md
# ===================================================================

SERVER="127.0.0.1"
ZONE="sudoers.lan"
PROXY_IP="192.168.0.2"

ensure_a() {
    local host="$1"
    if samba-tool dns query "$SERVER" "$ZONE" "$host" A -k yes 2>/dev/null \
            | grep -q "${PROXY_IP}$"; then
        echo "  ok    $host.$ZONE  →  $PROXY_IP  (ya existe)"
        return
    fi
    samba-tool dns add "$SERVER" "$ZONE" "$host" A "$PROXY_IP" -k yes \
        && echo "  +     $host.$ZONE  →  $PROXY_IP"
}

echo "==> Servicios web alojados en máquinas de admins (via proxy) ..."
ensure_a david
ensure_a nicolas

echo
echo "Listo. Verificar con: dig david.sudoers.lan / dig nicolas.sudoers.lan"