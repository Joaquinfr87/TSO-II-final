#!/bin/bash
# ===================================================================
# backup.sh — Backup del server con restic (nativo, vía cron).
#
# Ayuda: sudo bash server/backup.sh help   (config: .env.example)
#
# Subcomandos:
#   install     prepara el server (restic + repo + cron + logrotate). Una vez.
#   run         hace un backup completo (lo llama el cron a las 02:30).
#   check       verificación semanal de integridad (lee datos del repo).
#   status      estado del último backup, repo y disco.
#   snapshots   lista los snapshots del repo.
#
# La configuración NO se exporta al entorno: se lee del .env del repo
# (claves RESTIC_* y BACKUP_*). Ver .env.example.
# ===================================================================
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${BACKUP_ENV:-$ROOT/.env}"

WARNINGS=()
RUN_ACTIVE=0
STATUS_WRITTEN=0

# -------------------------------------------------------------------
# Utilidades de configuración y log
# -------------------------------------------------------------------

# env_get KEY → valor de la clave KEY en $ENV_FILE (sin exportar nada).
# Soporta valores con comillas y comentarios finales ("  # ...").
env_get() {
    local key="$1" val=""
    [ -r "$ENV_FILE" ] || return 1
    val="$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d= -f2-)" || true
    [ -n "$val" ] || return 1
    case "$val" in
        \"*\" | \'*\') ;;
        *) val="${val%%[[:space:]]#*}" ;;
    esac
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"
    case "$val" in
        \"*\") val="${val#\"}"; val="${val%\"}" ;;
        \'*\') val="${val#\'}"; val="${val%\'}" ;;
    esac
    printf '%s' "$val"
}

# cfg KEY [default] → variable de entorno, si no la del .env, si no el default.
cfg() {
    local key="$1" def="${2-}" val=""
    val="$(printenv "$key" 2>/dev/null || true)"
    if [ -z "$val" ]; then val="$(env_get "$key" || true)"; fi
    printf '%s' "${val:-$def}"
}

log() {
    local msg
    msg="$(printf '%s %s' "$(date '+%Y-%m-%d %H:%M:%S')" "$*")"
    printf '%s\n' "$msg"
    if [ -n "${LOG_FILE:-}" ] && [ -w "${LOG_FILE}" ]; then
        # 2>/dev/null va ANTES del >>: si el archivo no se puede abrir,
        # el error del shell no debe romper el script (log es best-effort).
        { printf '%s\n' "$msg" >>"$LOG_FILE"; } 2>/dev/null || true
    fi
}

warn() {
    WARNINGS+=("$*")
    log "AVISO: $*"
}

die() {
    log "ERROR: $*" >&2
    exit 1
}

# run_logged CMD... → ejecuta mostrando la salida en pantalla y en el log.
run_logged() {
    if [ -n "${LOG_FILE:-}" ] &&
        { [ -w "$LOG_FILE" ] || [ -w "$(dirname "$LOG_FILE")" ]; } 2>/dev/null; then
        "$@" 2>&1 | tee -a "$LOG_FILE"
    else
        "$@"
    fi
}

resolve_paths() {
    STATE_DIR="$(cfg BACKUP_STATE_DIR /var/lib/tso-backup)"
    STAGING="$STATE_DIR/staging"
    STATUS_FILE="$STATE_DIR/last-status"
    LOG_FILE="$(cfg BACKUP_LOG /var/log/tso-backup.log)"
    CRON_FILE="$(cfg BACKUP_CRON_FILE /etc/cron.d/tso-backup)"
    LOGROTATE_FILE="$(cfg BACKUP_LOGROTATE_FILE /etc/logrotate.d/tso-backup)"
    HOST_NAME="$(cfg BACKUP_HOSTNAME "$(hostname -s 2>/dev/null || hostname)")"
}

require_root() {
    if [ "$(cfg BACKUP_ALLOW_NONROOT 0)" = "1" ]; then return 0; fi
    [ "$(id -u)" = "0" ] || die "este subcomando necesita root: sudo bash server/backup.sh $1"
}

# -------------------------------------------------------------------
# Configuración restic
# -------------------------------------------------------------------

restic_env() {
    RESTIC_REPOSITORY="$(cfg RESTIC_REPOSITORY)"
    [ -n "$RESTIC_REPOSITORY" ] || die "falta RESTIC_REPOSITORY en $ENV_FILE (copiar de .env.example)"
    local pwfile
    pwfile="$(cfg RESTIC_PASSWORD_FILE)"
    if [ -n "$pwfile" ]; then
        [ -r "$pwfile" ] || die "RESTIC_PASSWORD_FILE=$pwfile no se puede leer"
        export RESTIC_PASSWORD_FILE="$pwfile"
        unset RESTIC_PASSWORD || true
    else
        RESTIC_PASSWORD="$(cfg RESTIC_PASSWORD)"
        [ -n "$RESTIC_PASSWORD" ] || die "falta RESTIC_PASSWORD en $ENV_FILE (generar: openssl rand -hex 32)"
        export RESTIC_PASSWORD
    fi
    export RESTIC_REPOSITORY

    KEEP_DAILY="$(cfg BACKUP_KEEP_DAILY 7)"
    KEEP_WEEKLY="$(cfg BACKUP_KEEP_WEEKLY 4)"
    KEEP_MONTHLY="$(cfg BACKUP_KEEP_MONTHLY 6)"
    KEEP_YEARLY="$(cfg BACKUP_KEEP_YEARLY 1)"
}

# El repo debe caer sobre el disco de backup montado (evita llenar /).
# Con BACKUP_ALLOW_SAME_FS=1 se salta (solo para probar).
repo_fs_check() {
    [ "$(cfg BACKUP_ALLOW_SAME_FS 0)" = "1" ] && return 0
    command -v mountpoint >/dev/null 2>&1 || return 0
    case "$RESTIC_REPOSITORY" in
        sftp:* | s3:* | rest:* | azure:* | gs:* | b2:* | rclone:*) return 0 ;;
    esac
    # Sube desde el repo hasta encontrar el mountpoint que lo contiene.
    local p="$RESTIC_REPOSITORY"
    while [ "$p" != "/" ]; do
        if [ -e "$p" ] && mountpoint -q "$p" 2>/dev/null; then return 0; fi
        p="$(dirname "$p")"
    done
    die "'$RESTIC_REPOSITORY' caería en el disco del sistema (sin montaje dedicado).
      Montá el disco de backup en el fstab o, solo para probar,
      setea BACKUP_ALLOW_SAME_FS=1"
}

repo_free_kb() {
    local p="$RESTIC_REPOSITORY"
    while [ ! -e "$p" ] && [ "$p" != "/" ]; do p="$(dirname "$p")"; done
    df -Pk "$p" 2>/dev/null | awk 'NR==2 {print $4}'
}

repo_space_check() {
    local min free
    min="$(cfg BACKUP_MIN_FREE_KB 1048576)"
    free="$(repo_free_kb)"
    [ -n "$free" ] || return 0
    if [ "$free" -lt "$min" ]; then
        die "disco casi lleno: ${free} KB libres (mínimo ${min} KB). Liberá espacio o bajá BACKUP_MIN_FREE_KB"
    fi
}

# -------------------------------------------------------------------
# Preparación del staging (lo que se agrega al snapshot de archivos)
# -------------------------------------------------------------------

samba_service_active() {
    if command -v systemctl >/dev/null 2>&1; then
        systemctl is-active --quiet samba-ad-dc 2>/dev/null && return 0
        systemctl is-active --quiet samba 2>/dev/null && return 0
    fi
    pgrep -x samba >/dev/null 2>&1
}

# Respaldo consistente del dominio AD → $STAGING/samba-domain/
# Con ticket Kerberos (o BACKUP_KINIT_USER) usa "domain backup online";
# sin ticket cae a "domain backup offline" (corre como root, sin password).
# Si todo falla, hace una copia caliente de los archivos (queda como AVISO).
samba_backup() {
    local out="$STAGING/samba-domain" rc=0 kinit_done="" server kuser kpass
    command -v samba-tool >/dev/null 2>&1 || { log "AD: samba-tool no instalado → se omite"; return 0; }
    if ! samba_service_active; then
        log "AD: el servicio Samba no está activo → se omite"
        return 0
    fi
    mkdir -p "$out"

    kuser="$(cfg BACKUP_KINIT_USER)"
    if [ -n "$kuser" ]; then
        kpass="$(cfg BACKUP_KINIT_PASSWORD)"
        if printf '%s\n' "$kpass" | kinit "$kuser" 2>/dev/null; then
            kinit_done=1
            log "AD: ticket Kerberos obtenido para $kuser"
        else
            warn "kinit falló para $kuser (se usará el modo sin ticket)"
        fi
    fi

    server="$(hostname -f 2>/dev/null || hostname -s)"
    # stdin cerrado a propósito: si algo pide password, falla en vez de colgarse.
    if klist -s 2>/dev/null; then
        log "AD: samba-tool domain backup online --server=$server"
        timeout "$(cfg BACKUP_SAMBA_TIMEOUT 900)" \
            samba-tool domain backup online --server="$server" --targetdir="$out" </dev/null || rc=1
    else
        log "AD: sin ticket Kerberos → samba-tool domain backup offline"
        timeout "$(cfg BACKUP_SAMBA_TIMEOUT 900)" \
            samba-tool domain backup offline --targetdir="$out" </dev/null || rc=1
    fi
    if [ -n "$kinit_done" ]; then kdestroy 2>/dev/null || true; fi

    if [ "$rc" -ne 0 ] || [ -z "$(ls -A "$out" 2>/dev/null)" ]; then
        warn "samba-tool domain backup falló → copia caliente de /var/lib/samba"
        local hot
        hot="$STAGING/samba-hotcopy-$(date +%Y%m%d).tar.gz"
        tar -C / -cpzf "$hot" var/lib/samba etc/samba etc/krb5.conf 2>/dev/null ||
            warn "no se pudo crear la copia caliente de Samba"
    fi
}

# Dump lógico de PostgreSQL (restaurable sin copia fría del volumen).
db_dump() {
    local cid db user pass out
    command -v docker >/dev/null 2>&1 || { log "DB: docker no disponible → se omite pg_dump"; return 0; }
    cid="$(timeout 20 docker ps --format '{{.ID}} {{.Image}}' 2>/dev/null |
        awk '$2 ~ /postgres/ {print $1; exit}')" || cid=""
    [ -n "$cid" ] || { log "DB: sin contenedor PostgreSQL activo → se omite pg_dump"; return 0; }

    mkdir -p "$STAGING/db"
    db="$(timeout 20 docker exec "$cid" printenv POSTGRES_DB 2>/dev/null || true)"
    user="$(timeout 20 docker exec "$cid" printenv POSTGRES_USER 2>/dev/null || true)"
    pass="$(timeout 20 docker exec "$cid" printenv POSTGRES_PASSWORD 2>/dev/null || true)"
    db="${db:-$(cfg POSTGRES_DB tso)}"
    user="${user:-$(cfg POSTGRES_USER tso)}"

    out="$STAGING/db/${db}-$(date +%Y%m%d-%H%M%S).dump"
    log "DB: pg_dump de '$db' en $cid"
    if PGPASSWORD="$pass" timeout "$(cfg BACKUP_DB_TIMEOUT 600)" \
        docker exec "$cid" pg_dump -U "$user" -Fc -d "$db" >"$out" && [ -s "$out" ]; then
        log "DB: pg_dump OK ($(du -h "$out" | cut -f1))"
    else
        rm -f "$out"
        warn "pg_dump de '$db' falló (el volumen completo igual se respalda)"
    fi
}

# Rutas que entran al snapshot.
collect_sources() {
    local p
    SOURCES=()
    for p in \
        /srv/samba \
        /var/lib/samba \
        /etc/samba \
        /etc/krb5.conf \
        /etc/nftables.conf \
        /etc/ssh/sshd_config \
        /etc/chrony/chrony.conf \
        "$ROOT" \
        "$STAGING"; do
        if [ -e "$p" ]; then SOURCES+=("$p"); fi
    done

    # Datos de todos los volúmenes Docker (leídos desde el host, como root).
    for p in /var/lib/docker/volumes/*/_data; do
        if [ -e "$p" ]; then SOURCES+=("$p"); fi
    done

    # Fuentes extra (BACKUP_EXTRA_PATHS="dir1 dir2")
    # shellcheck disable=SC2046
    for p in $(cfg BACKUP_EXTRA_PATHS); do
        if [ -e "$p" ]; then SOURCES+=("$p"); fi
    done

    [ "${#SOURCES[@]}" -gt 0 ] || die "no hay ninguna ruta que respaldar"
}

last_snapshot_id() {
    [ -n "${RESTIC_REPOSITORY:-}" ] || return 0
    if [ -z "${RESTIC_PASSWORD:-}" ] && [ -z "${RESTIC_PASSWORD_FILE:-}" ]; then return 0; fi
    restic snapshots --latest 1 --host "${HOST_NAME:-$(hostname -s 2>/dev/null || hostname)}" \
        </dev/null 2>/dev/null |
        awk '/^[0-9a-f][0-9a-f][0-9a-f][0-9a-f]/ {print $1; exit}' || true
}

write_status() {
    local state="$1" rc="$2" snap="${3:-}" dur="${4:-}"
    mkdir -p "$STATE_DIR"
    {
        echo "STATE=$state"
        echo "TIMESTAMP=$(date -Is)"
        echo "EXIT=$rc"
        echo "DURATION_S=$dur"
        echo "LAST_SNAPSHOT=${snap:-$(last_snapshot_id)}"
        echo "REPO=${RESTIC_REPOSITORY:-n/d}"
        echo "HOST=${HOST_NAME:-$(hostname -s 2>/dev/null || hostname)}"
        echo "WARNINGS=${#WARNINGS[@]}"
        if [ "${#WARNINGS[@]}" -gt 0 ]; then
            printf 'WARNING_DETAIL=%s\n' "${WARNINGS[*]}"
        fi
    } >"$STATUS_FILE"
    chmod 600 "$STATUS_FILE" 2>/dev/null || true
    STATUS_WRITTEN=1
}

# -------------------------------------------------------------------
# Subcomandos
# -------------------------------------------------------------------

install_cmd() {
    require_root install
    resolve_paths
    restic_env
    repo_fs_check
    repo_space_check

    if ! command -v restic >/dev/null 2>&1; then
        log "instalando restic ..."
        if command -v apt-get >/dev/null 2>&1; then
            DEBIAN_FRONTEND=noninteractive apt-get update -qq
            DEBIAN_FRONTEND=noninteractive apt-get install -y -qq restic
        else
            die "restic no está instalado y no hay apt-get. Instalalo y volvé a correr install"
        fi
    fi
    command -v restic >/dev/null 2>&1 || die "restic sigue sin estar disponible"
    log "restic: $(restic version | head -n1)"

    mkdir -p "$STATE_DIR"
    touch "$LOG_FILE" 2>/dev/null || true
    chmod 600 "$STATUS_FILE" 2>/dev/null || true

    if restic cat config >/dev/null 2>&1; then
        log "repo restic ya inicializado: $RESTIC_REPOSITORY"
    else
        log "inicializando repo restic en $RESTIC_REPOSITORY ..."
        mkdir -p "$(dirname "$RESTIC_REPOSITORY")" 2>/dev/null || true
        run_logged restic init
    fi

    mkdir -p "$(dirname "$CRON_FILE")"
    cat >"$CRON_FILE" <<EOF
# Generado por server/backup.sh install — NO editar a mano (re-correr install).
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/sbin:/bin:/usr/sbin:/usr/bin
MAILTO=root
# Backup diario (backup + retención + check rápido)
30 2 * * * root $SCRIPT_DIR/backup.sh run
# Verificación semanal de integridad con lectura de datos
15 4 * * 0 root $SCRIPT_DIR/backup.sh check
EOF
    chmod 644 "$CRON_FILE"
    log "cron instalado: $CRON_FILE"

    mkdir -p "$(dirname "$LOGROTATE_FILE")"
    cat >"$LOGROTATE_FILE" <<EOF
$LOG_FILE {
	weekly
	rotate 8
	compress
	missingok
	notifempty
}
EOF
    chmod 644 "$LOGROTATE_FILE"
    log "logrotate instalado: $LOGROTATE_FILE"

    echo
    echo "===================================================================="
    echo "  Backup instalado."
    echo "    repo    : $RESTIC_REPOSITORY"
    echo "    estado  : $STATUS_FILE"
    echo "    log     : $LOG_FILE"
    echo "    cron    : $CRON_FILE  (diario 02:30, check domingo 04:15)"
    echo "    retención: ${KEEP_DAILY}d / ${KEEP_WEEKLY}s / ${KEEP_MONTHLY}m / ${KEEP_YEARLY}a"
    echo
    echo "  Próximo paso: sudo bash server/backup.sh run"
    echo "  Ver en       : sudo bash server/backup.sh status"
    echo "  Restaurar    : sudo bash server/restore.sh help"
    echo "===================================================================="
}

run_cmd() {
    resolve_paths
    require_root run

    mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE" 2>/dev/null || true

    # No dos backups al mismo tiempo.
    exec 9>"$STATE_DIR/lock"
    flock -n 9 || die "ya hay un backup en curso (PID: $(cat "$STATE_DIR/lock.pid" 2>/dev/null || echo '?'))"
    echo $$ >"$STATE_DIR/lock.pid"

    # Desde acá cualquier error deja el estado en FAIL (lo ve status/monitoreo).
    RUN_ACTIVE=1
    RUN_STARTED="$(date +%s)"
    trap 'log "ERROR: comando falló (rc=$?) en línea $LINENO"' ERR
    trap 'on_run_exit' EXIT

    local started dur snap
    started="$RUN_STARTED"

    restic_env
    repo_fs_check
    repo_space_check

    command -v restic >/dev/null 2>&1 || die "restic no está instalado (corré: sudo bash server/backup.sh install)"
    restic cat config >/dev/null 2>&1 ||
        die "no se pudo abrir el repo $RESTIC_REPOSITORY
  ¿Existe RESTIC_REPOSITORY en .env y coincide con el disco montado?
  ¿Es correcta RESTIC_PASSWORD? (si el repo nunca existió: sudo bash server/backup.sh install)"
    # Limpia locks huérfanos (crash, reboot o un restic matado a mitad).
    # Solo borra locks inválidos: los de procesos vivos quedan.
    restic unlock </dev/null >/dev/null 2>&1 || true

    log "==== backup iniciado (repo: $RESTIC_REPOSITORY) ===="

    rm -rf "$STAGING"
    mkdir -p "$STAGING"
    samba_backup
    db_dump
    collect_sources

    log "respaldando ${#SOURCES[@]} rutas ..."
    run_logged restic backup "${SOURCES[@]}" \
        --exclude-file "$SCRIPT_DIR/backup-exclude.txt" \
        --tag tso \
        --host "$HOST_NAME"

    log "aplicando retención (${KEEP_DAILY}d / ${KEEP_WEEKLY}s / ${KEEP_MONTHLY}m / ${KEEP_YEARLY}a) + prune"
    run_logged restic forget \
        --host "$HOST_NAME" \
        --keep-daily "$KEEP_DAILY" --keep-weekly "$KEEP_WEEKLY" \
        --keep-monthly "$KEEP_MONTHLY" --keep-yearly "$KEEP_YEARLY" \
        --prune

    log "verificando integridad del repo (check)"
    run_logged restic check

    dur=$(($(date +%s) - started))
    snap="$(last_snapshot_id)"
    write_status OK 0 "$snap" "$dur"
    RUN_ACTIVE=0
    log "==== backup OK en ${dur}s (snapshot: ${snap:-n/d}) ===="
    if [ "${#WARNINGS[@]}" -gt 0 ]; then
        log "==== ${#WARNINGS[@]} avisos: ${WARNINGS[*]} ===="
    fi
}

on_run_exit() {
    local rc=$?
    if [ "$RUN_ACTIVE" != "1" ] || [ "$STATUS_WRITTEN" = "1" ]; then return 0; fi
    local dur=""
    if [ -n "${RUN_STARTED:-}" ]; then dur=$(($(date +%s) - RUN_STARTED)); fi
    write_status FAIL "$rc" "" "$dur"
    log "==== BACKUP FALLÓ (rc=$rc) — ver $LOG_FILE ===="
}

check_cmd() {
    require_root check
    resolve_paths
    restic_env
    command -v restic >/dev/null 2>&1 || die "restic no está instalado"
    local subset
    subset="$(cfg BACKUP_CHECK_SUBSET 10%)"
    restic unlock </dev/null >/dev/null 2>&1 || true
    log "==== verificación con lectura de datos ($subset) ===="
    run_logged restic check --read-data-subset="$subset"
    date -Is >"$STATE_DIR/last-check" 2>/dev/null || true
    log "==== verificación OK ===="
}

status_cmd() {
    resolve_paths
    restic_env
    echo "Repo    : $RESTIC_REPOSITORY"
    echo "Estado  : $STATUS_FILE"
    if [ -r "$STATUS_FILE" ]; then
        sed 's/^/  /' "$STATUS_FILE"
    else
        echo "  (sin ejecuciones registradas todavía)"
    fi
    case "$RESTIC_REPOSITORY" in
        sftp:* | s3:* | rest:* | azure:* | gs:* | b2:* | rclone:*) ;;
        *)
            local p="$RESTIC_REPOSITORY" free mp=""
            while [ "$p" != "/" ]; do
                if [ -e "$p" ] && mountpoint -q "$p" 2>/dev/null; then mp="$p"; break; fi
                p="$(dirname "$p")"
            done
            if [ -n "$mp" ]; then
                echo "Disco   : $mp montado OK"
            else
                echo "Disco   : ATENCIÓN — sin disco dedicado montado bajo $RESTIC_REPOSITORY"
            fi
            free="$(repo_free_kb)"
            if [ -n "$free" ]; then echo "Espacio : $((free / 1024)) MB libres"; fi
            ;;
    esac
    if [ -r "$CRON_FILE" ]; then
        echo "Cron    : $CRON_FILE"
        grep -v '^#' "$CRON_FILE" | grep -v '^$' | sed 's/^/  /' || true
    else
        echo "Cron    : NO instalado (corré: sudo bash server/backup.sh install)"
    fi
    echo
    echo "Últimos snapshots:"
    restic snapshots --latest 5 2>/dev/null | sed 's/^/  /' || echo "  (no se pudo listar el repo)"
}

snapshots_cmd() {
    resolve_paths
    restic_env
    run_logged restic snapshots "$@"
}

usage() {
    cat <<EOF
Uso: sudo bash server/backup.sh <subcomando>

  install      prepara el server: restic, repo restic, cron y logrotate
  run          hace un backup completo (lo ejecuta el cron a las 02:30)
  check        verificación semanal de integridad (lee los datos del repo)
  status       estado del último backup + disco + cron
  snapshots    lista los snapshots (acepta args de restic snapshots)

Config: claves RESTIC_* y BACKUP_* del .env del repo (ver .env.example)
Restore: sudo bash server/restore.sh help
EOF
}

main() {
    local cmd="${1:-}"
    if [ $# -gt 0 ]; then shift; fi
    case "$cmd" in
        install) install_cmd "$@" ;;
        run) run_cmd "$@" ;;
        check) check_cmd "$@" ;;
        status) status_cmd "$@" ;;
        snapshots | snaps) snapshots_cmd "$@" ;;
        -h | help | "") usage ;;
        *) usage; die "subcomando desconocido: $cmd" ;;
    esac
}

# Al sourcear (restore.sh) solo se cargan las funciones.
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    main "$@"
fi
