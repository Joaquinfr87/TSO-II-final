#!/bin/bash
set -e

# ========================================
# Entrypoint del servidor de correo
# Postfix (SMTP) + Dovecot (IMAP/POP3)
# Cuentas: por now locales (MAIL_USERS).
# TODO Fase 4: auth contra LDAP del DC (usuarios AD).
# ========================================

DOMAIN="${MAIL_DOMAIN:-mail.sudoers.lan}"
BASE_DOMAIN="${DOMAIN#*.}"      # "sudoers.lan"
MAIL_USERS="${MAIL_USERS:-}"

echo "============================================"
echo "  Servidor de Correo"
echo "  Dominio:    ${DOMAIN}"
echo "  Base domain: ${BASE_DOMAIN}"
echo "============================================"

# ========================================
# 1. Generar certificado SSL auto-firmado
# ========================================
SSL_DIR="/etc/ssl"
CERT_FILE="${SSL_DIR}/certs/mail.pem"
KEY_FILE="${SSL_DIR}/private/mail.key"

if [ ! -f "$CERT_FILE" ]; then
    echo ">>> Generando certificado SSL auto-firmado..."
    openssl req -new -x509 -days 3650 -nodes \
        -out "$CERT_FILE" \
        -keyout "$KEY_FILE" \
        -subj "/CN=${DOMAIN}/O=IT/C=AR" \
        2>/dev/null
    chmod 600 "$KEY_FILE"
    echo ">>> Certificado generado: ${CERT_FILE}"
else
    echo ">>> Certificado SSL ya existe, omitiendo generación"
fi

# ========================================
# 2. Configurar Postfix
# ========================================
echo ">>> Configurando Postfix..."
postconf -e "myhostname=${DOMAIN}"
postconf -e "mydomain=${BASE_DOMAIN}"
postconf -e "myorigin=${BASE_DOMAIN}"

# Habilitar puerto 587 (submission) con SASL
if ! grep -q '^submission' /etc/postfix/master.cf; then
    cat >> /etc/postfix/master.cf << 'SUBMISSION'

submission inet n       -       n       -       -       smtpd
  -o syslog_name=postfix/submission
  -o smtpd_tls_security_level=encrypt
  -o smtpd_sasl_auth_enable=yes
  -o smtpd_sasl_type=dovecot
  -o smtpd_sasl_path=private/auth
  -o smtpd_reject_unlisted_recipient=no
  -o smtpd_relay_restrictions=permit_sasl_authenticated,reject
  -o milter_macro_daemon_name=ORIGINATING
SUBMISSION
    echo ">>> Puerto 587 (submission) habilitado"
else
    echo ">>> Puerto 587 ya habilitado"
fi

# ========================================
# 3. Configurar Dovecot (configs ya copiadas)
# ========================================
echo ">>> Configurando Dovecot..."

# ========================================
# 4. Crear usuarios de correo (MAIL_USERS)
#    Formato: "user:pass user2:pass2" en .env
#    Vacío: no crea cuentas (Fase 4: usuarios desde AD/LDAP).
# ========================================
if [ -n "$MAIL_USERS" ]; then
    echo ">>> Creando usuarios de correo (MAIL_USERS)..."
    for ENTRY in $MAIL_USERS; do
        IFS=: read -r USERNAME _ PASSWORD <<< "$ENTRY"
        [ -z "$USERNAME" ] && continue

        if id "$USERNAME" &>/dev/null; then
            echo "    ok: ${USERNAME}"
        else
            useradd -m -s /bin/bash "$USERNAME"
            echo "${USERNAME}:${PASSWORD}" | chpasswd
            echo "    + ${USERNAME}"
        fi

        # Crear estructura Maildir
        MAILDIR="/home/${USERNAME}/Maildir"
        mkdir -p "${MAILDIR}/"{cur,new,tmp}
        chown -R "${USERNAME}:${USERNAME}" "${MAILDIR}"
        chmod -R 700 "${MAILDIR}"
        echo "    Maildir listo: ${USERNAME}"
    done
else
    echo ">>> MAIL_USERS vacío: sin cuentas locales."
    echo "    (Fase 4: las cuentas vendrán de LDAP/AD del DC)"
fi

# ========================================
# 5. Configurar aliases
# ========================================
echo ">>> Configurando aliases..."
cat > /etc/aliases << 'EOF'
root: postmaster
mailer-daemon: postmaster
postmaster: root
EOF
newaliases 2>/dev/null || true

# ========================================
# 6. Preparar directorios de sockets
# ========================================
rm -rf /var/run/dovecot
mkdir -p /var/run/dovecot
chown dovecot:dovecot /var/run/dovecot

mkdir -p /var/spool/postfix/private
chown postfix:postfix /var/spool/postfix/private

# ========================================
# 7. Iniciar servicios
# ========================================
echo ">>> Iniciando Postfix..."
postfix start

echo ">>> Verificando configuración Postfix..."
postconf -n | head -20

echo "============================================"
echo "  Servidor de correo listo"
echo "  SMTP:       ${DOMAIN}:25"
echo "  Submission: ${DOMAIN}:587"
echo "  IMAP:       ${DOMAIN}:143"
echo "  IMAPS:      ${DOMAIN}:993"
echo "  POP3:       ${DOMAIN}:110"
echo "  POP3S:      ${DOMAIN}:995"
echo "============================================"

# Dovecot en foreground (PID 1)
rm -rf /var/run/dovecot/*
exec dovecot -F