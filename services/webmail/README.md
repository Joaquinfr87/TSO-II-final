# Servicio: Webmail (Roundcube)

Roundcube es el webmail local para los usuarios de la organización. El navegador
accede por HTTPS al proxy de `dc1` y Roundcube conecta internamente con el
Postfix/Dovecot de `tso-mail`.

## Arquitectura

```text
Navegador ──HTTPS──► Nginx (192.168.0.2)
                         │  tso-net
                         ▼
                    tso-webmail:80
                         │  IMAP TLS 143 / SMTP TLS 587
                         ▼
                      tso-mail
```

- **URL:** `https://webmail.sudoers.lan`
- **Persistencia:** `webmail_db` para la base SQLite de Roundcube.
- **Correo:** Maildir persistente en el volumen `mail_data`, montado en `/home`.
- **Autenticación:** las cuentas locales definidas en `MAIL_USERS`.
- **AD/LDAP:** la integración con Samba AD queda para una etapa posterior.

## Variables

Definir en el `.env` de la raíz:

| Variable | Default | Descripción |
| --- | --- | --- |
| `MAIL_DOMAIN` | `mail.sudoers.lan` | Hostname del servidor de correo |
| `MAIL_USERS` | vacío | Cuentas `usuario:password usuario2:password2` |
| `ROUNDCUBE_IMAGE_TAG` | `1.7.4-apache` | Imagen de Roundcube |
| `ROUNDCUBE_DES_KEY` | requerido | Clave persistente para cifrar datos de sesión |

Generar una clave para `ROUNDCUBE_DES_KEY`:

```bash
openssl rand -hex 32
```

## Despliegue

En `dc1`:

```bash
cp .env.example .env
# completar MAIL_USERS, ROUNDCUBE_DES_KEY y secretos del compose
sudo kinit administrator
sudo bash dc/dns-records.sh
docker compose up -d --build mail webmail web
```

No se publica un puerto de Roundcube directamente: el acceso externo es
`https://webmail.sudoers.lan` y Nginx enruta al contenedor `tso-webmail:80`.

## Configuración

`config/config.inc.php` (montado en `/var/roundcube/config`, de solo lectura)
agrega encima de la config generada por la imagen:

- `proxy_whitelist` — confía en `X-Forwarded-Proto` del proxy: sin eso Roundcube
  cree que la petición es HTTP y la cookie de sesión no sale con `Secure`.
- `trusted_host` — solo acepta `webmail.sudoers.lan` como `Host`.
- `imap_conn_options` / `smtp_conn_options` — acepta el certificado autofirmado
  de `tso-mail` en las conexiones IMAP/SMTP internas con STARTTLS.
- `log_driver = stdout` → `docker compose logs webmail`.

El proxy (nginx) termina TLS con la CA interna de `services/web`.

## Verificación

```bash
docker compose ps mail webmail
docker compose logs --tail=100 mail webmail
curl -kI https://webmail.sudoers.lan          # 301 a HTTPS / 200 del login
```

Recorrido completo sin Thunderbird (todo por el navegador):

1. Entrar a `https://webmail.sudoers.lan` con una cuenta de `MAIL_USERS`
   (acepta `usuario` o `usuario@sudoers.lan`).
2. Enviar un mensaje a otro usuario de `MAIL_USERS`.
3. Cerrar sesión, entrar con el destinatario y ver el mensaje en el Inbox.

Errores típicos:

| Síntoma | Causa |
| --- | --- |
| `compose` aborta con `ROUNDCUBE_DES_KEY ... missing` | falta la clave en `.env` |
| Login rechazado, `imap-login: auth failed` en logs | cuenta no incluida en `MAIL_USERS` |
| `502 Bad Gateway` | contenedor `webmail` caído → `docker compose up -d webmail` |
| Aviso de certificado en el navegador | falta instalar `services/web/tls/ca.crt` |

Las contraseñas no se almacenan en el repositorio ni en el HTML del portal.

## Estado

- [x] Roundcube en Docker
- [x] Integración con Postfix/Dovecot (login IMAP + envío SMTP de probados)
- [x] Persistencia de sesiones (SQLite) y Maildir en volúmenes
- [x] Publicación HTTPS mediante Nginx (`webmail.sudoers.lan`)
- [x] Cookies de sesión `Secure` detrás del proxy (`proxy_whitelist`)
- [ ] Autenticación contra LDAP/Samba AD
- [ ] Certificados de correo firmados por la CA interna
