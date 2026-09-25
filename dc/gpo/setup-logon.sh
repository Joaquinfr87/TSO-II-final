#!/usr/bin/env bash
# =============================================================
# dc/gpo/setup-logon.sh — Distribuye el script de inicio de
# sesión (logon.cmd) e instala el fondo en el NETLOGON del DC.
# Luego asigna scriptPath a los usuarios del AD para que
# Windows lo ejecute en cada login.
#
# Uso:
#   sudo bash dc/gpo/setup-logon.sh                        # todos los usuarios AD
#   sudo bash dc/gpo/setup-logon.sh david nicolas joaquin  # usuarios puntuales
#   sudo bash dc/gpo/setup-logon.sh -w /ruta/al/fondo.jpg  # imagen de fondo
#
# Requisito: antes de correrlo, depositar dc/gpo/ooo-wall.jpg
# (o pasar -w con una imagen). Idempotente.
# =============================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WALL_SRC="${SCRIPT_DIR}/ooo-wall.jpg"
USERS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        -w|--wallpaper)
            WALL_SRC="$2"
            shift 2
            ;;
        *)
            USERS+=("$1")
            shift
            ;;
    esac
done

if [[ ! -f "${WALL_SRC}" ]]; then
    echo "ERROR: no encuentro la imagen de fondo (${WALL_SRC})."
    echo "       Depositá dc/gpo/ooo-wall.jpg o usá -w /ruta/al/fondo.jpg"
    exit 1
fi

echo "==> Localizando realm y NETLOGON"
REALM=$(grep -iE '^\s*realm\s*=' /etc/samba/smb.conf | awk '{print $3}' | tr 'A-Z' 'a-z')
if [[ -z "${REALM}" ]]; then
    echo "ERROR: no leo el realm de /etc/samba/smb.conf"
    exit 1
fi
NETLOGON="/var/lib/samba/sysvol/${REALM}/scripts"

echo "==> Instalando logon.cmd, wallpaper.ps1 y fondo en ${NETLOGON}"
# logon.cmd debe llevar bit de ejecucion: Samba mapea FILE_EXECUTE
# a la X del filesystem; con 0644 los clientes leen pero no ejecutan.
sudo install -m 0755 -o root -g root "${SCRIPT_DIR}/logon.cmd" "${NETLOGON}/logon.cmd"
sudo install -m 0644 -o root -g root "${SCRIPT_DIR}/wallpaper.ps1" "${NETLOGON}/wallpaper.ps1"
sudo install -m 0644 -o root -g root "${WALL_SRC}" "${NETLOGON}/ooo-wall.jpg"

# Certificado de CA interna (para que el logon.cmd lo distribuya a los clientes Windows)
CA_SRC="$(cd "${SCRIPT_DIR}/../.." && pwd)/services/web/tls/ca.crt"
if [ -f "${CA_SRC}" ]; then
    sudo install -m 0644 -o root -g root "${CA_SRC}" "${NETLOGON}/ca.crt"
    echo "==> ca.crt instalado en ${NETLOGON}/ca.crt"
else
    echo "ATENCIÓN: no se encontró ${CA_SRC}"
    echo "          Generá los certificados primero con:"
    echo "          sudo bash services/web/tls-gen.sh"
    echo "          y volvé a correr este script."
fi

if [[ ${#USERS[@]} -eq 0 ]]; then
    mapfile -t USERS < <(sudo samba-tool user list | grep -vE '^(administrator|krbtgt)$')
fi

echo "==> Asignando scriptPath a ${#USERS[@]} usuarios"
LDIF="$(mktemp)"
trap 'rm -f "${LDIF}"' EXIT
DC="dc=${REALM//./,dc=}"
for u in "${USERS[@]}"; do
    DN="cn=${u},cn=Users,${DC}"
    printf 'dn: %s\nchangetype: modify\nreplace: scriptPath\nscriptPath: logon.cmd\n\n' "${DN}" >> "${LDIF}"
done

sudo ldbmodify -H /var/lib/samba/private/sam.ldb "${LDIF}"

echo "==> Verificación"
for u in "${USERS[@]}"; do
    printf '  %-12s -> ' "${u}"
    sudo samba-tool user show "${u}" 2>/dev/null | awk -F': ' '/scriptPath/ {print $2}' \
        || { echo "OK"; continue; }
    sudo samba-tool user show "${u}" 2>/dev/null | grep -q 'scriptPath: logon.cmd' \
        && echo "logon.cmd" || echo "??"
done

echo "Listo. Probá iniciando sesión en Windows con un usuario del dominio."
echo "Para revertir: 'sudo samba-tool user edit <usuario>' y quitar scriptPath,"
echo "y 'sudo rm -f ${NETLOGON}/logon.cmd ${NETLOGON}/ooo-wall.jpg'."