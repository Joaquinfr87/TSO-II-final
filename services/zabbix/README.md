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
| `zabbix-agent` | agent2 container — host de prueba (métricas reales: agent nativo) |

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
2. **Monitorear dc1** (`192.168.0.2`): instalar `zabbix-agent2` nativo en dc1
   con `Server=192.168.0.3`, `ServerActive=192.168.0.3:10051`. En
   `server/nftables.conf` abrir el puerto del agente para el origen del
   monitoreo:
   ```
   tcp dport 10050 ip saddr 192.168.0.3 accept
   ```
3. **Monitorear clientes de la LAN**: agent pasivo en cada cliente; el server
   los consulta directo. Abrir en el firewall del cliente: `tcp dport 10050`
   con origen `192.168.0.3`.
4. **Monitorear el server zabbix mismo** (métricas reales del SO): instalar
   `zabbix-agent2` nativo apuntando a `localhost` (el contenedor
   `zabbix-agent` solo ve el contenedor).

## Notas

- Imágenes oficiales Zabbix 7.0 (`alpine-7.0-latest`) — pin en `.env`.
- DB password en `.env` del server (fuera del repo, no versionar).
- Alertas: configurar Media Type "Email" contra el Postfix del dominio
  (`mail.sudoers.lan`) cuando el correo esté activo.