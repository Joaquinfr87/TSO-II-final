# Servicio: Correo (Postfix + Dovecot)

Servidor de correo con **Postfix** (SMTP) y **Dovecot** (IMAP/POP3) para la
intranet `sudoers.lan`. Heredado y adaptado del lab.

## Arquitectura

```
Cliente ── 587 ──► Postfix (MTA/SMTP) ── SASL ─► Dovecot (auth)
Cliente ── 143 ──► Dovecot (IMAP)      ── lee ─► ~/Maildir/
```

- **Cuentas:** ahora vía `MAIL_USERS` (env). **Fase 4:** cuentas = usuarios
  AD autenticando contra LDAP del DC (ver TODO en `10-auth.conf`).
- **Entrega:** Maildir en `/home/<usuario>/Maildir`, persistente mediante
  `mail_data:/home`.
- **Webmail:** Roundcube en `webmail.sudoers.lan`, publicado por el proxy HTTPS.

## Puertos

| Puerto | Protocolo | Uso |
| --- | --- | --- |
| 25 | SMTP | Transferencia entre servidores |
| 587 | SMTP submission | Clientes envían con auth |
| 110 / 995 | POP3 / POP3S | Acceso por descarga |
| 143 / 993 | IMAP / IMAPS | Acceso sincronizado |

## Uso

```bash
# cuentas iniciales (opcional) en .env:
#   MAIL_USERS="joaquin:Pass1! david:Pass2!"
docker compose up -d --build mail webmail
docker compose logs -f mail webmail
```

## Verificación (Fase actual)

```bash
# SMTP básico
telnet localhost 25
HELO test
MAIL FROM:<a@sudoers.lan>
RCPT TO:<joaquin@sudoers.lan>
DATA
hola
.
QUIT

# submission con AUTH (lo que usa el webmail)
python3 - <<'EOF'
import smtplib, ssl
from email.message import EmailMessage
m = EmailMessage(); m['From']='joaquin@sudoers.lan'; m['To']='david@sudoers.lan'
m['Subject']='prueba'; m.set_content('hola')
with smtplib.SMTP('mail.sudoers.lan', 587) as s:
    s.ehlo(); s.starttls(context=ssl._create_unverified_context()); s.ehlo()
    s.login('joaquin', 'PASS'); s.send_message(m)
EOF
```

El acceso principal para los usuarios es `https://webmail.sudoers.lan`; los
usuarios pueden usar Roundcube sin configurar Thunderbird. Para clientes de
correo opcionales: IMAP `mail.sudoers.lan:143` y SMTP
`mail.sudoers.lan:587`, ambos con STARTTLS.

## Variables de entorno

| Variable | Default | Descripción |
| --- | --- | --- |
| `MAIL_DOMAIN` | `mail.sudoers.lan` | Hostname del MTA |
| `MAIL_USERS` | `joaquin:… david:…` | Cuentas `usuario:pass usuario2:pass2`; vacío = sin cuentas locales (no usable el webmail) |

Roundcube acepta tanto `usuario` como `usuario@sudoers.lan`; Dovecot normaliza
el dominio (`auth_username_format = %Ln`) para consultar la cuenta local.

## Nota de persistencia

El volumen `mail_data` se monta en `/home`, que es donde Postfix y Dovecot
guardan los Maildir. Si el volumen ya tenía datos de una versión anterior
montada en `/var/mail`, hay que migrarlos a `/home/<usuario>/Maildir` antes de
continuar.

Verificado: al recrear el contenedor (`docker compose up -d --force-recreate
mail`) el `entrypoint` vuelve a crear las cuentas y **los Maildir y las
contraseñas se conservan** (mismo UID, datos en el volumen).

## Estado

- [x] Postfix: SMTP + submission 587 con SASL/Dovecot, STARTTLS
- [x] Dovecot: IMAP/POP3, Maildir, certificado autofirmado
- [x] Cuentas parametrizadas por `MAIL_USERS` (persisten entre recreaciones)
- [x] Envío con AUTH + entrega local verificado (Maildir del destinatario)
- [x] Roundcube publicado en `webmail.sudoers.lan`
- [ ] **Fase 4:** auth contra LDAP del DC (usuarios AD, sin duplicar cuentas)
- [ ] **Fase 4:** registros MX/SPF en el DNS del DC
- [ ] **Fase 5:** certificados de la CA interna en lugar de autofirmados

## Referencias

- Arquitectura: [`docs/arquitectura.md`](../../docs/arquitectura.md)