# Servicio: Monitoreo (Netdata / Grafana) — PENDIENTE

Carpeta reservada para el **monitoreo** del servidor y los servicios.

## Plan (Fase 6)

- **Netdata** (rápido: host + contenedores Docker).
- y/o **Grafana + Prometheus** para dashboards históricos y alertas.
- Alerta por **correo interno** (`tso-mail`).
- Publicado por el proxy en `dashboard.sudoers.lan` (`services/web/nginx.conf`).

## Pendiente de desarrollo

- [ ] Dockerfile / imagen(es)
- [ ] Metric collectors (node_exporter, cadvisor / API Docker)
- [ ] Bloque(s) en `docker-compose.yml`
- [ ] Server block en `services/web/nginx.conf`
- [ ] README del servicio

## Referencias

- Arquitectura: [`docs/arquitectura.md`](../../docs/arquitectura.md) — §13 Backups y monitoreo