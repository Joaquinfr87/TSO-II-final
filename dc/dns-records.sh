#!/bin/bash
set -euo pipefail

# ===================================================================
# dc/dns-records.sh — Registros A de servicios públicos (idempotente).
#
# Crea/verifica en el DNS AD los nombres que publican servicios web.
# Todos apuntan SIEMPRE al proxy (192.168.0.2), NUNCA a la máquina.
#
# USAR el nombre del DC (no 127.0.0.1): samba-tool dns contra loopback
# falla al bindear el RPC (NT_STATUS_INVALID_PARAMETER en el puerto
# dinámico). Con dc1.sudoers.lan (~192.168.0.2) no da ese problema.
#
# Uso (EN EL DC, con ticket Kerberos de administrador):
#   sudo kinit administrator        # pide el password una sola vez
#   sudo bash dc/dns-records.sh
#
# Guía de publicación: docs/publicar-servicios-admin.md
# ===================================================================

SERVER="dc1.sudoers.lan"
ZONE="sudoers.lan"
PROXY_IP="192.168.0.2"

ensure_a() {
    local host="$1"
    if samba-tool dns query "$SERVER" "$ZONE" "$host" A --use-kerberos=required 2>/dev/null \
            | grep -q "${PROXY_IP}$"; then
        echo "  ok    $host.$ZONE  →  $PROXY_IP  (ya existe)"
        return
    fi
    samba-tool dns add "$SERVER" "$ZONE" "$host" A "$PROXY_IP" --use-kerberos=required \
        && echo "  +     $host.$ZONE  →  $PROXY_IP"
}

echo "==> Servicios web alojados en máquinas de admins (via proxy) ..."
ensure_a david
ensure_a nicolas

echo
echo "Listo. Verificar con: dig david.sudoers.lan / dig nicolas.sudoers.lan"