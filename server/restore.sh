#!/bin/bash
# ===================================================================
# restore.sh — Asistente de restauración de los backups (restic).
#
# Ayuda: sudo bash server/restore.sh help
#
# Subcomandos:
#   list                       lista snapshots (acepta args de restic)
#   files [SNAP] [--target D] [--include RUTA ...]
#                              restaura archivos / shares / configs
#   repo [SNAP] [--target D]   restaura el repo del proyecto (+ .env + TLS)
#   domain [SNAP]              extrae el respaldo del dominio AD e imprime
#                              los pasos de recuperación
#   database [SNAP] [--yes]    restaura el dump de PostgreSQL en tso-db
#   volume <nombre> [SNAP]     extrae un volumen Docker e imprime los pasos
#
# Todos escriben en $BACKUP_STATE_DIR/restore/ por defecto: primero se
# extrae a un lado y recién después (con confirmación) se pisa nada.
# ===================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=backup.sh
source "$SCRIPT_DIR/backup.sh"

SNAPSHOT="latest"
TARGET=""
INCLUDES=()
POS=()
YES=0

usage_restore() {
    cat <<EOF
Uso: sudo bash server/restore.sh <subcomando> [opciones]

  list [--latest N]              lista los snapshots del repo
  files [SNAP] [--target DIR] [--include RUTA ...]
                                 restaura archivos (shares, configs, .env, ...)
  repo [SNAP] [--target DIR]     restaura el repo completo del proyecto
  domain [SNAP]                  extrae el respaldo del dominio AD e imprime
                                 los pasos para recuperarlo
  database [SNAP] [--yes]        restaura el dump de PostgreSQL en tso-db
  volume <nombre> [SNAP]         extrae un volumen Docker e imprime los pasos

  --target DIR   destino (por defecto: $STATE_DIR/restore/<fecha>)
  --include RUTA solo restaura esa ruta del snapshot (se puede repetir)
  --yes / -y     no pedir confirmación (para scripts)

Ejemplos:
  sudo bash server/restore.sh list
  sudo bash server/restore.sh files --include /srv/samba/departamentos/marketing
  sudo bash server/restore.sh repo --target /tmp/repo-restaurado
  sudo bash server/restore.sh database --yes
  sudo bash server/restore.sh volume tso-it_mail_data
EOF
}

parse_args() {
    SNAPSHOT="latest"
    TARGET=""
    INCLUDES=()
    POS=()
    YES=0
    while [ $# -gt 0 ]; do
        case "$1" in
            --target)
                [ $# -ge 2 ] || die "--target necesita un valor"
                TARGET="$2"
                shift 2
                ;;
            --include)
                [ $# -ge 2 ] || die "--include necesita una ruta"
                INCLUDES+=("$2")
                shift 2
                ;;
            --yes | -y) YES=1; shift ;;
            -h | --help) usage_restore; exit 0 ;;
            -*) die "opción desconocida: $1" ;;
            *)
                POS+=("$1")
                shift
                ;;
        esac
    done
}

default_target() {
    printf '%s/restore/%s' "$STATE_DIR" "$(date +%Y%m%d-%H%M%S)"
}

confirm() {
    local prompt="$1" ans=""
    if [ "$YES" = "1" ]; then return 0; fi
    if [ ! -t 0 ]; then
        die "este paso necesita confirmación interactiva (o usá --yes)"
    fi
    read -r -p "$prompt [s/N] " ans
    case "$ans" in
        s | S | si | SI | sí | Sí) return 0 ;;
        *) return 1 ;;
    esac
}

restore_paths() {
    local dest="$1" snap="$2" label="$3"
    shift 3
    local paths=("$@") p args=()
    mkdir -p "$dest"
    for p in "${paths[@]}"; do args+=(--include "$p"); done
    log "restaurando $label (snapshot: $snap) → $dest"
    if [ "${#args[@]}" -gt 0 ]; then
        run_logged restic restore "$snap" --target "$dest" "${args[@]}" </dev/null
    else
        run_logged restic restore "$snap" --target "$dest" </dev/null
    fi
    if [ -z "$(ls -A "$dest" 2>/dev/null)" ]; then
        die "no se restauró nada en $dest
  Probablemente esa ruta no existe en el snapshot: mirá los paths con
    bash server/restore.sh list"
    fi
}

# -------------------------------------------------------------------
# files / repo
# -------------------------------------------------------------------

cmd_files() {
    parse_args "$@"
    SNAPSHOT="${POS[0]:-latest}"
    local dest="${TARGET:-$(default_target)}"
    if [ "${#INCLUDES[@]}" -eq 0 ]; then
        die "indicá qué restaurar, p. ej.:
  sudo bash server/restore.sh files --include /srv/samba/departamentos
  sudo bash server/restore.sh files --include /etc/samba/smb.conf"
    fi
    if [ "$dest" = "/" ]; then
        log "AVISO: destino '/' → restic escribe directo sobre los paths del snapshot (pisa lo incluido)"
    fi
    restore_paths "$dest" "$SNAPSHOT" "archivos" "${INCLUDES[@]}"
    echo
    if [ "$dest" = "/" ]; then
        echo "Restaurado en su lugar original ($SNAPSHOT)."
    else
        echo "Restaurado en: $dest"
        echo "Revisalo y movelo a su lugar con (por ejemplo):"
        echo "  sudo rs -a \"$dest/\" /"
    fi
}

cmd_repo() {
    parse_args "$@"
    SNAPSHOT="${POS[0]:-latest}"
    local dest="${TARGET:-$(default_target)}"
    restore_paths "$dest" "$SNAPSHOT" "repo del proyecto" "$ROOT"
    echo
    echo "Repo restaurado en: $dest"
    echo "Para usarlo:"
    echo "  diff -r \"$dest\" \"$ROOT\"        # qué cambió"
    echo "  sudo cp -a \"$dest/.env\" \"$ROOT/.env\"   # recuperar solo los secretos"
    echo "  sudo bash services/web/tls-gen.sh         # si falta services/web/tls/"
}

# -------------------------------------------------------------------
# Dominio AD
# -------------------------------------------------------------------

cmd_domain() {
    parse_args "$@"
    SNAPSHOT="${POS[0]:-latest}"
    local dest="${TARGET:-$(default_target)}"
    restore_paths "$dest" "$SNAPSHOT" "respaldo del dominio AD" \
        "$STATE_DIR/staging/samba-domain"

    local tarball
    tarball="$(find "$dest" -type f \( -name '*.tar.bz2' -o -name '*.tar.gz' -o -name '*.tar.xz' \) 2>/dev/null | head -n1 || true)"
    if [ -z "$tarball" ]; then
        log "No encontré el tarball del dominio en $dest"
        log "Puede que ese snapshot sea anterior a la instalación del backup, o"
        log "que samba-tool haya fallado (ver AVISOS en: server/backup.sh status)"
        exit 1
    fi
    cat <<EOF

Respaldo del dominio extraído:
  $tarball

RECUPERACIÓN DEL DOMINIO (solo si el DC se perdió o la BD está dañada).
Leé bien cada paso antes de correr nada:

  # 1) Copiá el tarball al server (si se restaura en otra máquina)
  # 2) Detener Samba
  sudo systemctl stop samba-ad-dc
  # 3) Guardar el estado actual (por si hay que volver atrás)
  sudo mv /var/lib/samba /var/lib/samba.bak.\$(date +%s)
  # 4) Restaurar el dominio desde el tarball
  sudo samba-tool domain backup restore \\
      --backup-file="$tarball" \\
      --targetdir=/var/lib/samba \\
      --host-ip=192.168.0.2
  # 5) Levantar y verificar
  sudo systemctl start samba-ad-dc
  sudo samba-tool domain level show
  sudo kinit administrator

Si el DC está sano y solo querés recuperar usuarios/GPOs, es más fácil
re-correr dc/add-users-groups.sh, dc/dns-records.sh y dc/gpo/ (son idempotentes).
EOF
}

# -------------------------------------------------------------------
# Base de datos (PostgreSQL de tso-db)
# -------------------------------------------------------------------

postgres_cid() {
    command -v docker >/dev/null 2>&1 || return 1
    timeout 20 docker ps --format '{{.ID}} {{.Image}}' 2>/dev/null |
        awk '$2 ~ /postgres/ {print $1; exit}'
}

cmd_database() {
    parse_args "$@"
    SNAPSHOT="${POS[0]:-latest}"
    local dest="${TARGET:-$(default_target)}" cid dump db user
    restore_paths "$dest" "$SNAPSHOT" "dump de PostgreSQL" \
        "$STATE_DIR/staging/db"

    dump="$(find "$dest" -type f -name '*.dump' 2>/dev/null | sort | tail -n1 || true)"
    [ -n "$dump" ] || die "no encontré ningún *.dump en $dest (¿el snapshot es anterior al backup?)"

    cid="$(postgres_cid || true)"
    if [ -z "$cid" ]; then
        echo
        echo "No hay contenedor PostgreSQL corriendo. Restauración manual:"
        echo "  docker compose up -d database"
        echo "  docker exec -i tso-db pg_restore -U tso -d tso --clean --if-exists < \"$dump\""
        exit 1
    fi
    db="$(timeout 20 docker exec "$cid" printenv POSTGRES_DB 2>/dev/null || true)"
    user="$(timeout 20 docker exec "$cid" printenv POSTGRES_USER 2>/dev/null || true)"
    db="${db:-$(cfg POSTGRES_DB tso)}"
    user="${user:-$(cfg POSTGRES_USER tso)}"

    echo
    echo "Dump a restaurar : $dump"
    echo "Contenedor       : $cid  (base: $db, usuario: $user)"
    echo "ATENCIÓN: pg_restore --clean borra los objetos actuales de '$db'."
    confirm "¿Restaurar '$db' desde ese dump?" || { log "cancelado"; exit 1; }

    log "restaurando $db ..."
    docker exec -i "$cid" pg_restore -U "$user" -d "$db" --clean --if-exists <"$dump"
    log "restauración de '$db' completada"
}

# -------------------------------------------------------------------
# Volúmenes Docker
# -------------------------------------------------------------------

cmd_volume() {
    parse_args "$@"
    local vol="${POS[0]:-}" dest
    [ -n "$vol" ] || die "indicá el volumen: sudo bash server/restore.sh volume <nombre> [SNAPSHOT]
  (los nombres están en: docker volume ls)"
    SNAPSHOT="${POS[1]:-latest}"
    dest="${TARGET:-$(default_target)}"
    restore_paths "$dest" "$SNAPSHOT" "volumen $vol" \
        "/var/lib/docker/volumes/$vol/_data"

    cat <<EOF

Volumen '$vol' extraído en:
  $dest/var/lib/docker/volumes/$vol/_data

RECUPERACIÓN (el volumen vivo no se toca mientras corre el contenedor):
  docker stop <contenedor-que-usa-$vol>
  sudo rs -a "$dest/var/lib/docker/volumes/$vol/_data/" "/var/lib/docker/volumes/$vol/_data/"
  docker start <contenedor>
EOF
}


# -------------------------------------------------------------------

main_restore() {
    local cmd="${1:-help}"
    if [ $# -gt 0 ]; then shift; fi
    resolve_paths
    case "$cmd" in
        help | -h | "")
            usage_restore
            ;;
        list | snapshots)
            restic_env
            run_logged restic snapshots "$@"
            ;;
        files) restic_env; cmd_files "$@" ;;
        repo) restic_env; cmd_repo "$@" ;;
        domain) restic_env; cmd_domain "$@" ;;
        database | db) restic_env; cmd_database "$@" ;;
        volume | vol) restic_env; cmd_volume "$@" ;;
        *)
            usage_restore
            die "subcomando desconocido: $cmd"
            ;;
    esac
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main_restore "$@"
fi
