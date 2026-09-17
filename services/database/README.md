# Servicio: Base de datos (PostgreSQL)

Servidor de base de datos **PostgreSQL 15** para las apps internas (wiki,
webmail, logs del proxy, monitoreo). Heredado del lab sin cambios de fondo.

## Archivos

| Archivo | Descripción |
| --- | --- |
| `Dockerfile` | Imagen con PostgreSQL 15 (Debian bookworm) |
| `entrypoint.sh` | Inicializa el cluster, configura red, crea usuario/base del `.env` y arranca |

## Uso

```bash
docker compose up -d --build database
```

## Verificación

```bash
docker compose exec database pg_isready -h 127.0.0.1 -p 5432
docker compose exec database psql -h 127.0.0.1 -U tso -d tso -c 'SELECT version();'
```

## Variables de entorno

| Variable | Default | Descripción |
| --- | --- | --- |
| `DB_PORT` | `5432` | Puerto publicado en el host |
| `POSTGRES_USER` | `tso` | Usuario creado al iniciar |
| `POSTGRES_PASSWORD` | `tso` | Contraseña (**cambiar** en `.env`) |
| `POSTGRES_DB` | `tso` | Base creada al iniciar |

## Seguridad / integración

- En el firewall el 5432 queda restringido a IPs admin (`server/nftables.conf`).
- Otras apps de `tso-net` se conectan por `tso-db:5432` con estas credenciales.
- El grupo AD `srv-dba` es quien debería tener acceso documentado a las bases.

## Estado

- [x] Imagen + entrypoint (cluster, usuario y base automáticos)
- [x] Escucha en todas las interfaces (`tso-net` + host)
- [ ] Definir esquemas/tablas por app (Fase 5)
- [ ] MariaDB solo si alguna app lo requiere (docs dice "si hace falta")

## Referencias

- Arquitectura: [`docs/arquitectura.md`](../../docs/arquitectura.md)