# Servicio: DHCP (Kea) — red única 192.168.0.0/24

Servidor DHCP basado en **Kea** que asigna IP, puerta de enlace, DNS, dominio
y NTP a los equipos de la red. Solo este servicio corre con
`network_mode: host`.

## Archivos

| Archivo | Descripción |
| --- | --- |
| `Dockerfile` | Imagen con `kea-dhcp4-server` |
| `kea-dhcp4.conf` | Plantilla (los `__TOKENS__` los reemplaza el entrypoint) |
| `entrypoint.sh` | Aplica variables del `.env` y arranca Kea |

## Uso

```bash
docker compose up -d --build dhcp
```

## Red (importante)

Kea usa **broadcast** en `67/udp` (BOOTP/DHCP). Eso **no** funciona mapeando
puerto a través de un bridge de Docker: por eso el servicio declara
`network_mode: host` en el compose (escucha en las interfaces físicas del
host) y **no** tiene bloque `ports:` ni `networks:`.

> Lección tomada del lab: en el lab Kea corría en bridge publicando `67:67/udp`
> y un cliente físico no lo encontraba por broadcast. Acá se aplica host network.
> Al correr Kea en el modo DNS del DC, el propio DC es quien entrega el DHCP → DNS.

## Plan de red (192.168.0.0/24)

| Zona | Rango | Destino |
| --- | --- | --- |
| Fija | `192.168.0.1 – .49` | Infraestructura, impresoras, servidores (reservas) |
| Reservas | `192.168.0.50 – .99` | Equipos fijos (contabilidad, marketing, cajas) |
| Pool | `192.168.0.100 – .199` | Resto de clientes |

Opciones entregadas: **DNS = 192.168.0.2** (el DC), **dominio = sudoers.lan**,
**NTP = 192.168.0.2** (el DC), **gateway = 192.168.0.1** (router TP-Link).

### Reservas DHCP por MAC

Se configuran en `.env` con `DHCP_RESERVATIONS` (formato
`"MAC=IP=hostname;…"`). El entrypoint las convierte al array `reservations`
del subnet de Kea:

```bash
DHCP_RESERVATIONS="aa:bb:cc:dd:ee:01=192.168.0.50=pc-joaquin;aa:bb:cc:dd:ee:02=192.168.0.51=pc-nicolas"
```

Los PCs de los admins ocupan `.50–.52` (coincide con `admin_ips` del
firewall). Verificar concesiones tras el cambio:

```bash
docker compose exec dhcp cat /var/lib/kea/kea-leases4.csv
```

> Cuando Kea toma el servicio, **apagar el DHCP del router** (TP-Link) para
> evitar doble concesión.

## Variables de entorno

| Variable | Default | Descripción |
| --- | --- | --- |
| `DHCP_SUBNET` | `192.168.0.0/24` | Red que atiende Kea |
| `DHCP_POOL` | `192.168.0.100 - 192.168.0.199` | Rango que entrega |
| `DHCP_DNS` | `192.168.0.2` | DNS anunciado a los clientes (el DC) |
| `DHCP_GATEWAY` | `192.168.0.1` | Puerta de enlace (`routers`) |
| `DHCP_NTP` | `192.168.0.2` | Servidor NTP (el DC) |
| `DHCP_RESERVATIONS` | (vacío) | Reservas por MAC: `MAC=IP=hostname;…` |
| `DNS_DOMAIN` | `sudoers.lan` | Dominio interno |

## Verificación

```bash
docker compose logs dhcp                      # resume subred/pool/DNS/NTP/reservas
docker compose exec dhcp cat /var/lib/kea/kea-leases4.csv   # concesiones
sudo dhclient -v <iface>                      # en un cliente de la LAN
```

## Estado

- [x] Imagen + entrypoint con tokens (subnet/pool/dns/dominio/gateway/ntp)
- [x] `network_mode: host` declarado en el compose
- [x] Reservas por MAC vía `DHCP_RESERVATIONS` en el `.env`
- [ ] DDNS hacia el DC (registros A de los clientes) si se necesita

## Referencias

- Arquitectura: [`docs/arquitectura.md`](../../docs/arquitectura.md)
- Documentación Kea: <https://kea.readthedocs.io/>