#!/bin/bash
set -e

# ========================================
# Entrypoint para PostgreSQL
# Inicializa el cluster (si el volumen está
# vacío), configura la red y crea el
# usuario/base de datos del .env
# ========================================

VER="${PG_VERSION:-15}"
PGBIN="/usr/lib/postgresql/${VER}/bin"
PGDATA="/var/lib/postgresql/${VER}/main"
PGCONF="/etc/postgresql/${VER}/main"
CLUSTER="${VER}/main"

POSTGRES_USER="${POSTGRES_USER:-postgres}"
POSTGRES_PASSWORD="${POSTGRES_PASSWORD:-postgres}"
POSTGRES_DB="${POSTGRES_DB:-tso}"

echo "============================================"
echo "  PostgreSQL ${VER}"
echo "  Usuario:  ${POSTGRES_USER}"
echo "  Base:     ${POSTGRES_DB}"
echo "============================================"

# 1) Si el volumen está vacío, inicializar el cluster
if [ ! -s "${PGDATA}/PG_VERSION" ]; then
    echo ">>> Inicializando cluster PostgreSQL ${VER}"
    mkdir -p "${PGDATA}"
    chown -R postgres:postgres "$(dirname "${PGDATA}")"
    runuser -u postgres -- "${PGBIN}/initdb" -D "${PGDATA}" --encoding=UTF8 --locale=C.UTF-8
fi

# 2) Escuchar en todas las interfaces y autenticar con contraseña
pg_conftool ${VER} main set listen_addresses '*'
pg_conftool ${VER} main set password_encryption scram-sha-256

# 3) Permitir conexiones con contraseña desde cualquier equipo
HBA="${PGCONF}/pg_hba.conf"
if ! grep -q "^host.*all.*all.*0.0.0.0/0" "${HBA}"; then
    echo "host all all 0.0.0.0/0 scram-sha-256" >> "${HBA}"
fi
echo ">>> Red y autenticación configuradas"

# 4) Arranque temporal para preparar usuario y base
pg_ctlcluster "${CLUSTER}" start

# 5) Crear el usuario o actualizar su contraseña
cat > /tmp/setup-users.sql <<EOF
DO \$\$
BEGIN
   IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '${POSTGRES_USER}') THEN
      CREATE ROLE ${POSTGRES_USER} LOGIN PASSWORD '${POSTGRES_PASSWORD}';
   ELSE
      ALTER ROLE ${POSTGRES_USER} WITH LOGIN PASSWORD '${POSTGRES_PASSWORD}';
   END IF;
END
\$\$;
EOF
runuser -u postgres -- psql -U postgres -d postgres -f /tmp/setup-users.sql

# 6) Crear la base de datos si no existe
if [ "${POSTGRES_DB}" != "postgres" ]; then
    EXISTS_DB=$(runuser -u postgres -- psql -U postgres -d postgres -tAc \
        "SELECT 1 FROM pg_database WHERE datname='${POSTGRES_DB}'")
    if [ "${EXISTS_DB}" != "1" ]; then
        runuser -u postgres -- createdb -O "${POSTGRES_USER}" "${POSTGRES_DB}"
        echo ">>> Base de datos '${POSTGRES_DB}' creada (dueño: ${POSTGRES_USER})"
    fi
fi

# 7) Detener el arranque temporal
pg_ctlcluster "${CLUSTER}" stop

echo ">>> PostgreSQL listo, escuchando en 0.0.0.0:5432"

# 8) Foreground como postgres (PID 1), con la config de Debian
exec runuser -u postgres -- "${PGBIN}/postgres" \
    -D "${PGDATA}" \
    -c "config_file=${PGCONF}/postgresql.conf" \
    -c "hba_file=${HBA}"