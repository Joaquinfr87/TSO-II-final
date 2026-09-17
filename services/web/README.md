# Servicio: Web / Proxy inverso (Nginx)

Nginx sirve el **portal de la intranet** y actúa como **proxy inverso** de los
servicios publicados por nombre (`*.sudoers.lan`). Es la única puerta web
hacia los servicios de la organización.

## Archivos

| Archivo | Descripción |
| --- | --- |
| `Dockerfile` | Imagen `nginx:1.27-alpine` |
| `nginx.conf` | Server blocks: proxy a print/portainer + sitio principal + default |
| `public/` | Portal estático de la intranet |

## Mapa actual

| Nombre | Backend |
| --- | --- |
| `sudoers.lan` / `web.sudoers.lan` / `www` | estático (`public/`) |
| `print.sudoers.lan` | `tso-print:631` (CUPS) |
| `portainer.sudoers.lan` | `tso-portainer:9000` (Portainer HTTP interno) |
| `webmail.sudoers.lan` | `tso-webmail:80` — **comentado, Fase 4** |
| `dashboard.sudoers.lan` | monitoreo — **Fase 6** |

Para publicar un servicio nuevo:

1. Levantar su contenedor en `tso-net`.
2. Agregar el `server {}` correspondiente en `nginx.conf` (mismo patrón).
3. `docker compose up -d --build web`.

## Uso

```bash
docker compose up -d --build web
```

## Próximamente

- [ ] HTTPS con **CA interna** (el proxy termina TLS). Hoy solo HTTP.
- [ ] Activar webmail/monitoring/apps cuando existan sus contenedores.

## Referencias

- Arquitectura: [`docs/arquitectura.md`](../../docs/arquitectura.md)