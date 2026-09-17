# Servicio: Webmail (Roundcube) — PENDIENTE

Carpeta reservada para el servicio **Roundcube** (correo por navegador).

## Plan (Fase 4)

- Contenedor `webmail` con Roundcube.
- Backend IMAP: `tso-mail` (Dovecot, puerto 143) con usuarios AD/LDAP.
- Publicado por el proxy en `webmail.sudoers.lan` (`services/web/nginx.conf`).

## Pendiente de desarrollo

- [ ] Dockerfile / imagen
- [ ] Configuración (`config.inc.php`)
- [ ] Bloque en `docker-compose.yml`
- [ ] Server block en `services/web/nginx.conf`
- [ ] README del servicio

## Referencias

- Arquitectura: [`docs/arquitectura.md`](../../docs/arquitectura.md) — §8 Correo
- Proxy: [`../web/README.md`](../web/README.md)