#!/bin/sh
# ============================================================
# services/filemanager/entrypoint.sh — Filebrowser (gestor de archivos web)
#
# Prepara la BD antes de arrancar el server:
#   * 1ª vez:  crea la BD, baja el mínimo de longitud de clave y crea el
#     administrador (FILES_ADMIN_*).
#   * siempre: sincroniza los usuarios de .env (FILES_USERS) y fija los
#     modos de lo que se cree desde la web (fileMode/dirMode) para que el
#     grupo del share pueda escribir también por SMB.
# El contenedor corre como root con grupo primario FILES_GID (si se define)
# para que los archivos creados queden root:<grupo-del-share>.
# ============================================================
set -e

CFG="${FB_CONFIG:-/config/settings.json}"
DB="/database/filebrowser.db"
MIN_LEN="${FILES_MIN_PASS_LEN:-10}"
ADMIN_USER="${FILES_ADMIN_USER:-admin}"
ADMIN_PASS="${FILES_ADMIN_PASS:?Falta FILES_ADMIN_PASS en .env}"

# ---- claves: Filebrowser se queja si son mas cortas que minimumPasswordLength
BAD=""
[ "${#ADMIN_PASS}" -lt "$MIN_LEN" ] && BAD="$ADMIN_USER"
for ENTRY in ${FILES_USERS:-}; do
    P="${ENTRY#*:}"
    [ "${#P}" -lt "$MIN_LEN" ] && BAD="$BAD ${ENTRY%%:*}"
done
if [ -n "$BAD" ]; then
    echo "ERROR: claves de menos de $MIN_LEN caracteres para:$BAD" >&2
    echo "       (baja FILES_MIN_PASS_LEN en .env si queres claves mas cortas)" >&2
    exit 1
fi

# settings.json (puerto 80, root=/srv, database) lo aporta la imagen.
# Sin este archivo, -c se ignora y todo cae al /filebrowser.db default.
if [ ! -f "$CFG" ]; then
    cp -a /defaults/settings.json "$CFG"
    echo ">>> settings.json creado en $CFG"
fi

FIRST=0
if [ ! -f "$DB" ]; then
    filebrowser -c "$CFG" config init >/dev/null 2>&1
    filebrowser -c "$CFG" config set --minimumPasswordLength "$MIN_LEN" >/dev/null
    FIRST=1
    echo ">>> base de datos creada (minimumPasswordLength=$MIN_LEN)"
fi

# ¿existe el usuario? (users ls = tabla, 2da columna = username)
have() {
    filebrowser -c "$CFG" users ls 2>/dev/null | awk 'NR>1 {print $2}' | grep -qx "$1"
}

sync_user() {
    U="$1"; P="$2"; EXTRA="$3"
    if have "$U"; then
        if filebrowser -c "$CFG" users update "$U" --password "$P" >/dev/null 2>&1; then
            echo "    = $U (clave sincronizada)"
        else
            echo "    ! AVISO: no pude sincronizar la clave de $U" >&2
        fi
    else
        # shellcheck disable=SC2086
        filebrowser -c "$CFG" users add "$U" "$P" $EXTRA >/dev/null
        echo "    + $U (creado$([ -n "$EXTRA" ] && echo ", admin"))"
    fi
}

sync_user "$ADMIN_USER" "$ADMIN_PASS" "--perm.admin"
for ENTRY in ${FILES_USERS:-}; do
    U="${ENTRY%%:*}"
    P="${ENTRY#*:}"
    [ -z "$U" ] && continue
    sync_user "$U" "$P" ""
done

# ---- permisos de lo que se cree desde la web ----
filebrowser -c "$CFG" config set \
    --minimumPasswordLength "$MIN_LEN" \
    --fileMode "${FILES_FILE_MODE:-0664}" \
    --dirMode "${FILES_DIR_MODE:-0775}" >/dev/null 2>&1
echo ">>> archivos nuevos: ${FILES_FILE_MODE:-0664} | carpetas: ${FILES_DIR_MODE:-0775}"

# umask 002: si no, el 022 por defecto deja los archivos en 0644 (sin
# escritura del grupo) y nadie del share podria editarlos por SMB.
umask "${FILES_UMASK:-002}"
echo ">>> umask: $(umask)"

echo "============================================"
echo "  Gestor de archivos"
echo "  Carpetas:  /srv/departamentos, /srv/respaldo"
echo "  Admin:     $ADMIN_USER"
if [ "$FIRST" = "1" ]; then
    echo "  (primer arranque: cambiar la clave desde Settings)"
fi
echo "============================================"

exec filebrowser -c "$CFG"
