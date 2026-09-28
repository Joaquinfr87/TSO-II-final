# Servicio: Zabbix (monitoreo) — corre en un server Debian FÍSICO

Zabbix **server + web** alojado en un **server Debian físico dedicado** de la
LAN: hostname `zabbix`, IP fija `192.168.0.3` (rango infraestructura
`.1–.49`, reserva por MAC vía Kea). **No es una VM**: es una máquina más de la
red, alcanzable directo desde todos (sin NAT, sin DNAT).

Por eso tiene su **propio docker-compose**: se despliega EN ESE SERVER, no en
dc1. NO va en el `docker-compose.yml` raíz (ese es para dc1).

## Topología (simple, sin NAT)

```
   clientes de la LAN ──[agent 10050]── zabbix (192.168.0.3)
                                               │ :80 (web pública)
                                               ▼
                          zabbix.sudoers.lan → 192.168.0.3
```

- Zabbix alcanza toda la LAN **directo** (agents **pasivos** en los clientes).
- La UI se accede directamente: `http://zabbix.sudoers.lan`

## Composición

| Servicio | Imagen / rol |
| --- | --- |
| `postgres` | `postgres:16-alpine` — BD (volumen `pgdata`) |
| `zabbix-server` | `zabbix/zabbix-server-pgsql` — recolección + alertas (10051) |
| `zabbix-web` | `zabbix/zabbix-web-nginx-pgsql` — UI (puerto público 80) |
| `zabbix-agent` | agent2 contenedor — **opcional**: el agente nativo (`install-agent.sh zabbix`) lo reemplaza |

## Despliegue (en el server zabbix)

```bash
cd services/zabbix
cp .env.example .env        # completar DB_PASSWORD
docker compose up -d
docker compose ps           # verificar (postgres healthy, server/web/agent up)
```

La web queda en `http://zabbix.sudoers.lan` (el contenedor escucha internamente en
`8080`) — login por defecto
`Admin/zabbix` (**cambiar ya**).

## Integración con el dominio

1. **DNS**: `zabbix.sudoers.lan` resuelve directamente a `192.168.0.3`.
   En el DC, con ticket de administrador:
   ```bash
   sudo kinit administrator
   sudo bash dc/dns-records.sh
   ```
   La UI queda disponible en `http://zabbix.sudoers.lan`.
2. **Monitorear dc1** (`192.168.0.2`): instalar el agente nativo
   (repo + config + grupo docker en un solo paso):
   ```bash
   git pull
   sudo bash services/zabbix/install-agent.sh dc1
   sudo bash server/deploy.sh      # recarga nftables (abre 10050 desde .3)
   ```
   El script deja `Server=192.168.0.3`, `ServerActive=192.168.0.3:10051`,
   `Hostname=dc1`. El firewall en `server/nftables.conf` ya tiene la regla
   `tcp dport 10050 ip saddr 192.168.0.3 accept`.
3. **Monitorear clientes de la LAN**: agent pasivo en cada cliente; el server
   los consulta directo. Abrir en el firewall del cliente: `tcp dport 10050`
   con origen `192.168.0.3`.
4. **Monitorear el server zabbix mismo** (métricas reales del SO): en
   `192.168.0.3`:
   ```bash
   git pull
   sudo bash services/zabbix/install-agent.sh zabbix
   ```
   Deja `Server=127.0.0.1,::1,172.16.0.0/12,192.168.0.0/24` (el server corre
   en contenedor: la fuente es el bridge docker) y
   `ServerActive=127.0.0.1:10051`. El host en Zabbix se llama
   `Zabbix server` (interfaz `192.168.0.3:10050`).
   El contenedor `zabbix-agent` del compose queda **opcional**: el agente
   nativo lo reemplaza (si querés sacarlo:
   `docker compose rm -sf zabbix-agent`).

## Notas

- Imágenes oficiales Zabbix 7.0 (`alpine-7.0-latest`) — pin en `.env`.
- DB password en `.env` del server (fuera del repo, no versionar).
- Alertas: configurar Media Type "Email" contra el Postfix del dominio
  (`mail.sudoers.lan`) cuando el correo esté activo.