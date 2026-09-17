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
- **Entrega:** Maildir en volumen persistente.
- **Webmail:** Roundcube (Fase 4) publicado por el proxy.

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
docker compose up -d --build mail
docker compose logs -f mail
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
```

Con un cliente (Thunderbird): entrada IMAP `mail.sudoers.lan:143`,
salida SMTP `mail.sudoers.lan:587`, usuario = cuenta de `MAIL_USERS`,
STARTTLS en ambos.

## Variables de entorno

| Variable | Default | Descripción |
| --- | --- | --- |
| `MAIL_DOMAIN` | `mail.sudoers.lan` | Hostname del MTA |
| `MAIL_USERS` | `(vacío)` | Cuentas `usuario:pass usuario2:pass2`; vacío = sin cuentas locales |

## Estado

- [x] Postfix: SMTP + submission 587 con SASL/Dovecot, STARTTLS
- [x] Dovecot: IMAP/POP3, Maildir, certificado autofirmado
- [x] Cuentas parametrizadas por `MAIL_USERS`
- [ ] **Fase 4:** auth contra LDAP del DC (usuarios AD, sin duplicar cuentas)
- [ ] **Fase 4:** registros MX/SPF en el DNS del DC + webmail Roundcube
- [ ] **Fase 5:** certificados de la CA interna en lugar de autofirmados

## Referencias

- Arquitectura: [`docs/arquitectura.md`](../../docs/arquitectura.md)