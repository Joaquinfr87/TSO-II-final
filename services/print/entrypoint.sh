#!/bin/bash
set -e

# Crear usuario admin si no existe (CUPS requiere un usuario con permisos)
ADMIN_USER="${CUPS_ADMIN_USER:-admin}"
ADMIN_PASS="${CUPS_ADMIN_PASS:-admin}"

if ! id "$ADMIN_USER" &>/dev/null; then
    useradd -m -s /bin/bash "$ADMIN_USER"
fi

# Establecer contraseña del usuario admin
echo "${ADMIN_USER}:${ADMIN_PASS}" | chpasswd

# Agregar usuario al grupo administradores de CUPS
groupadd -f lpadmin
usermod -aG lpadmin "$ADMIN_USER"

# Asegurar que los directorios necesarios existan
mkdir -p /var/spool/cups-pdf/OUT /var/log/cups /var/run/cups
chmod 1777 /var/spool/cups-pdf/OUT
touch /var/log/cups/page_log

# Iniciar el daemon CUPS en primer plano
cupsd -f &
CUPSD_PID=$!

# Esperar a que CUPS esté listo (reintentar hasta 30 veces)
echo ">>> Esperando que CUPS inicie..."
for i in $(seq 1 30); do
    if lpstat -h localhost:631 -r &>/dev/null; then
        echo ">>> CUPS listo."
        break
    fi
    if ! kill -0 "$CUPSD_PID" 2>/dev/null; then
        echo "ERROR: cupsd terminó inesperadamente"
        exit 1
    fi
    sleep 1
done

# Supresión de la advertencia de drivers deprecados
export CUPS_DATADIR=/usr/share/cups

# Verificar que la impresora virtual PDF exista, si no crearla
# (con reintentos porque CUPS a veces responde lpstat antes de
#  estar listo para operaciones de admin)
if ! lpstat -h localhost:631 -p PDF &>/dev/null; then
    echo ">>> Creando impresora virtual PDF..."
    PDF_CREATED=1
    for i in $(seq 1 30); do
        if lpadmin -h localhost:631 -p PDF \
            -E \
            -v "cups-pdf:/" \
            -m lsb/usr/cups-pdf/CUPS-PDF_opt.ppd \
            -o printer-is-shared=true \
            -o job-sheets=none 2>/dev/null; then
            echo ">>> Impresora virtual PDF creada correctamente."
            PDF_CREATED=0
            break
        fi
        sleep 1
    done
    if [ "$PDF_CREATED" -ne 0 ]; then
        echo "ERROR: no se pudo crear la impresora PDF"
        exit 1
    fi
fi

# Activar la cola para aceptar trabajos
for i in $(seq 1 15); do
    if cupsenable -h localhost:631 PDF && cupsaccept -h localhost:631 PDF; then
        break
    fi
    sleep 1
done

echo "============================================"
echo "  Servidor de impresión CUPS iniciado"
echo "  Interfaz web: http://localhost:631"
echo "  Impresora:    PDF (virtual)"
echo "  Admin user:   ${ADMIN_USER}"
echo "============================================"

# Esperar al daemon CUPS manteniendo el contenedor vivo
wait "$CUPSD_PID"