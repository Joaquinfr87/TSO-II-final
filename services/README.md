# services/ — Servicios en contenedores (heredados y adaptados del lab)

Cada servicio tiene su carpeta con Dockerfile y configuración. El
`docker-compose.yml` de la raíz es la fuente de verdad que los declara.

| Carpeta | Servicio | Estado |
| --- | --- | --- |
| [`dhcp/`](dhcp/README.md) | Kea DHCP (host network) | listo (adaptado del lab) |
| [`web/`](web/README.md) | Nginx proxy inverso `*.sudoers.lan` | listo (adaptado) |
| [`mail/`](mail/README.md) | Postfix + Dovecot | listo (auth LDAP pendiente) |
| [`database/`](database/README.md) | PostgreSQL | listo (heredado) |
| [`print/`](print/README.md) | CUPS + PDF virtual | listo (heredado) |
| [`dns/`](dns/README.md) | Bind9 — **RETIRADO**: el DNS lo da el DC | documentado |
| [`zabbix/`](zabbix/README.md) | Zabbix (monitoreo) — **VM 192.168.122.4, compose propio** | nuevo |
| [`webmail/`](webmail/README.md) | Roundcube (Fase 4) | **pendiente (vacío)** |
| [`monitoring/`](monitoring/README.md) | Netdata / Grafana — **superado por Zabbix** | descartado |
| [`apps/`](apps/README.md) | Apps internas (Fase 5) | **pendiente (vacío)** |

> `files` del lab quedó **fuera**: los recursos SMB los sirve el DC nativo
> (`dc/shares.conf`). NFS/share aislado se suma dentro de `apps/` si hace falta.

## Cómo agregar un servicio nuevo

1. Crear `services/<nombre>/` con `Dockerfile` (+ config) y `README.md`.
2. Agregar el bloque en el `docker-compose.yml` raíz.
3. Si expone web por nombre, agregar el server block en `services/web/nginx.conf`.
4. Documentar en `docs/` y en este índice.

## Reglas

- Ningún puerto del DC nativo se publica: `53, 88, 389, 445, 139, 636`.
- Sin secretos: contraseñas en `.env`, nunca en el repo.
- Kea es el único servicio con `network_mode: host`.