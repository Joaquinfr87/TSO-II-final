# Servicio: Web / Proxy inverso (Nginx)

Nginx sirve el **portal de la intranet** y actúa como **proxy inverso** de los
servicios publicados por nombre (`*.sudoers.lan`). Es la única puerta web
hacia los servicios de la organización. **Termina TLS** con una CA interna.

## Archivos

| Archivo | Descripción |
| --- | --- |
| `Dockerfile` | Imagen `nginx:1.27-alpine` (80 + 443) |
| `nginx.conf` | Server blocks: HTTPS + redirect 80→443, proxy a print/portainer, sitio principal |
| `tls-gen.sh` | Genera CA interna + certificado wildcard `*.sudoers.lan` (NO versionado) |
| `public/` | Portal estático + páginas del equipo (`equipo/*.html`) |

## Mapa actual

| Nombre | Backend |
| --- | --- |
| `sudoers.lan` / `web.sudoers.lan` / `www` | estático (`public/`) |
| `print.sudoers.lan` | `tso-print:631` (CUPS) |
| `portainer.sudoers.lan` | `tso-portainer:9000` (Portainer HTTP interno) |
| `webmail.sudoers.lan` | `tso-webmail:80` — **comentado, Fase 4** |
| `dashboard.sudoers.lan` | monitoreo — **Fase 6** |
| `joaquin.sudoers.lan` | estático — página del equipo (`/equipo/joaquin.html`) |
| `david.sudoers.lan` | `192.168.0.51:8080` — servicio web de la máquina de David |
| `nicolas.sudoers.lan` | `192.168.0.52:8080` — servicio web de la máquina de Nicolás |

Todo `http://…` redirige a `https://…` (301). El proxy solo habla HTTP hacia
los backends internos; el TLS lo termina nginx.

`david`/`nicolas` son servicios web corriendo **en las máquinas de los admins**
(.51/.52) expuestos por este proxy. Roles, puerto y registro:
[`docs/publicar-servicios-admin.md`](../../docs/publicar-servicios-admin.md).

## HTTPS / TLS

El certificado cubre `*.sudoers.lan` (wildcard) más el nombre de IP del server.
Se firma con una **CA interna** que NO se versiona (está en `.gitignore`).

Primera vez en el server:

```bash
sudo bash services/web/tls-gen.sh      # crea services/web/tls/{ca,server}.{crt,key}
docker compose up -d --build web
```

Regenerar el certificado del server (conserva la CA): borrar
`services/web/tls/server.crt` + `server.key` y correr de nuevo `tls-gen.sh`.

**Clientes:** para confiar en el HTTPS, instalar `services/web/tls/ca.crt`
como CA de confianza (en Linux: `/usr/local/share/ca-certificates/`) o importarla
en el navegador/O.S. Sin eso verás el aviso de certificado no confiable.

## Uso

```bash
docker compose up -d --build web
```

## Próximamente

- [ ] Activar webmail/monitoring/apps cuando existan sus contenedores.

## Referencias

- Arquitectura: [`docs/arquitectura.md`](../../docs/arquitectura.md)