#!/bin/bash
set -euo pipefail
# ============================================================
# password-policy.sh — Política de contraseñas del dominio AD
#
#   sudo bash dc/password-policy.sh
# ============================================================

echo "==> Aplicando política de contraseñas..."
samba-tool domain passwordsettings set \
    --min-pwd-length=10 \
    --min-pwd-age=1 \
    --max-pwd-age=90 \
    --history-length=24 \
    --complexity=on

echo
echo "==> Política vigente:"
samba-tool domain passwordsettings show