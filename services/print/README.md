# Servicio: Impresión (CUPS + impresora virtual PDF)

Servidor de impresión basado en **CUPS** con impresora virtual **cups-pdf**
(convierte trabajos de impresión en PDF). Heredado del lab sin cambios de
fondo.

## Uso

```bash
# puerto del host: CUPS_PORT=1631 (evita conflicto con CUPS del host)
docker compose up -d --build print
```

Acceso por web: `http://print.sudoers.lan` (proxied) o `http://<server>:1631`
(usuario `admin` / pass del `.env`; `CUPS_ADMIN_PASS`).

## Verificación

```bash
# Desde el host
lp -d PDF -h localhost:${CUPS_PORT:-1631} archivo.txt

# Desde otro contenedor en tso-net
lp -d PDF -h tso-print:631 archivo.txt

# PDFs generados
docker compose exec print ls /var/spool/cups-pdf/OUT/
```

## Variables de entorno

| Variable | Default | Descripción |
| --- | --- | --- |
| `CUPS_PORT` | `1631` | Puerto del host hacia el CUPS del contenedor |
| `CUPS_ADMIN_USER` | `admin` | Usuario admin de CUPS |
| `CUPS_ADMIN_PASS` | `admin` | Password (**cambiar** en `.env`) |

## Estado

- [x] CUPS + PDF virtual + interfaz web
- [ ] Impresoras físicas conectadas al server
- [ ] Compartir impresoras por SMB (para clientes Windows) si se requiere
- [ ] Auth de producción (hoy `admin`/pass simple)

## Referencias

- Arquitectura: [`docs/arquitectura.md`](../../docs/arquitectura.md)