# Servicio: Monitoreo (Prometheus + Grafana + Alertmanager)

Stack de monitoreo y alertas **corriendo en dc1 como contenedores**
(`docker-compose.yml` → servicios `prometheus`, `grafana`, `alertmanager`,
`node-exporter`, `cadvisor`, `blackbox-exporter`).

> **Zabbix no se toca**: sigue en el server físico `zabbix`
> (`192.168.0.3`, [`services/zabbix/`](../zabbix/README.md)). Este stack es
> complementario: métricas + alertas por correo hacia los administradores.

## Componentes

| Contenedor | Qué hace | Acceso |
| --- | --- | --- |
| `tso-prometheus` | Recolecta métricas cada 30s y evalúa alertas | `127.0.0.1:9090` (solo host) |
| `tso-alertmanager` | Agrupa alertas y manda el correo | `127.0.0.1:9093` (solo host) |
| `tso-grafana` | Dashboards | <https://grafana.sudoers.lan> (proxy) y `127.0.0.1:3000` |
| `tso-node-exporter` | Métricas del host + `backup.prom` | solo red interna |
| `tso-cadvisor` | Métricas de los contenedores | solo red interna |
| `tso-blackbox` | Sondas: ¿responde cada servicio/DNS/URL? | solo red interna |

Prometheus y Alertmanager **no se publican**: para verlos desde una máquina
de admin:

```bash
ssh -L 9090:127.0.0.1:9090 -L 9093:127.0.0.1:9093 joaquin@192.168.0.2
# y abrir http://127.0.0.1:9090  y  http://127.0.0.1:9093
```

## Qué mide

- **Host (dc1)** — CPU, memoria, disco, red, load, uptime (`node-exporter`).
- **Contenedores `tso-*`** — CPU, memoria, red y si siguen reportando
  (`cadvisor`).
- **Servicios** — sonda TCP al DC (`53, 88, 389, 445`), a los contenedores
  (`tso-web`, `tso-mail`, `tso-db`, `tso-print`, `tso-files`, `tso-webmail`,
  `tso-portainer`), sonda DNS (`sudoers.lan` en el DC) y HTTP 2xx
  (Grafana, webmail) — `blackbox-exporter`.
- **Backup** — `server/backup.sh` exporta
  `/var/lib/tso-backup/backup.prom` (estado, última corrida, duración,
  avisos) y `node-exporter` lo lee con
  `--collector.textfile.directory`.

## Alertas (por correo)

Reglas en [`prometheus/rules/`](prometheus/rules/):

| Archivo | Alertas |
| --- | --- |
| `host.yml` | `HostSinMonitoreo`, `HostCPUAlto`, `HostMemoriaBaja`, `HostDiscoBajo`, `HostReiniciado` |
| `contenedores.yml` | `ContenedorCaido`, `ContenedorComeCPU` |
| `servicios.yml` | `ServicioInalcanzable`, `ServicioLento` |
| `backup.yml` | `BackupFallido`, `BackupDesactualizado`, `BackupNuncaEjecutado`, `BackupConAvisos` |

Destino (`alertmanager/alertmanager.yml`):
`joaquin@sudoers.lan, david@sudoers.lan, nicolas@sudoers.lan`.
El correo sale por el contenedor `tso-mail` (Postfix de dc1): `mynetworks`
ya incluye la red Docker y cualquier `*@sudoers.lan` se entrega en el
Maildir local — **no hay que tocar Postfix**.

## Dashboards (Grafana)

JSON versionados en [`grafana/dashboards/`](grafana/dashboards/), cargados
por provisioning (`grafana/provisioning/`), carpeta **TSO**:

- **TSO - Host (dc1)**
- **TSO - Contenedores**
- **TSO - Servicios y Backup**

La datasource es `Prometheus` con **uid fijo `prometheus`**
(`grafana/provisioning/datasources/prometheus.yml`).

## Uso

```bash
docker compose up -d prometheus grafana alertmanager   # stack básico
docker compose up -d node-exporter cadvisor blackbox-exporter
docker compose logs -f prometheus
```

Validar configs antes de aplicar (también lo hace `server/deploy.sh`):

```bash
docker run --rm --entrypoint promtool -v "$PWD/services/monitoring/prometheus:/p:ro" \
  prom/prometheus:v3.15.0 check config /p/prometheus.yml
docker run --rm --entrypoint amtool -v "$PWD/services/monitoring/alertmanager:/a:ro" \
  prom/alertmanager:v0.34.1 check-config /a/alertmanager.yml
```

Recargar Prometheus tras cambiar reglas:

```bash
curl -X POST http://127.0.0.1:9090/-/reload
```

## Requisitos en `.env`

```bash
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=...    # openssl rand -base64 18
GF_SECRET_KEY=...             # openssl rand -hex 32
```

## Detalles a tener en cuenta

- **Firewall:** `server/nftables.conf` necesita la regla
  `tcp dport { 53, 88, 389, 445 } ip saddr 172.16.0.0/12 accept` para que
  las sondas del contenedor alcancen el DC nativo (INPUT `policy drop`).
- **DNS:** `grafana.sudoers.lan → 192.168.0.2` se crea con
  `dc/dns-records.sh` (`ensure_a grafana "$PROXY_IP"`).
- El certificado wildcard `*.sudoers.lan` de `services/web/tls/` ya cubre
  `grafana.sudoers.lan`.

## Referencias

- Arquitectura: [`docs/arquitectura.md`](../../docs/arquitectura.md) — §13
- Zabbix (server físico): [`services/zabbix/README.md`](../zabbix/README.md)
