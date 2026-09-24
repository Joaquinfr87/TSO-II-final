# Servicio: Zabbix (monitoreo) — corre en la VM 192.168.122.4

Zabbix **server + web** alojado en la **VM dedicada** `192.168.122.4`
(libvirt/KVM, red NAT `192.168.122.0/24`).

Por eso tiene su **propio docker-compose**: se despliega DENTRO de la VM,
no en dc1. NO va en el `docker-compose.yml` raíz (ese es para el host).

## Composición

| Servicio | Imagen / rol |
| --- | --- |
| `postgres` | `postgres:16-alpine` — BD (volumen `pgdata`) |
| `zabbix-server` | `zabbix/zabbix-server-pgsql` — recolección + alertas (10051) |
| `zabbix-web` | `zabbix/zabbix-web-nginx-pgsql` — UI (puerto 8080) |
| `zabbix-agent` | agent2 container — host de prueba "vm-zabbix" |

## Despliegue (dentro de la VM)

```bash
cd services/zabbix
cp .env.example .env        # completar DB_PASSWORD
docker compose up -d
docker compose ps           # verificar (postgres healthy, server/web/agent up)
```

La web queda en `http://192.168.122.4:8080` — login por defecto
`Admin/zabbix` (**cambiar ya**).

## Alcance — CRÍTICO (por el NAT)

- La VM **sale** a la red del host: el server puede **consultar agents** de los
  clientes de la LAN (polling a `10050`, origen que ven = `192.168.0.2`).
- La LAN **NO entra** a la VM: nadie abre una conexión hacia `192.168.122.4`.
  La web se publica vía el proxy de dc1 → `zabbix.sudoers.lan -> http://192.168.122.4:8080`
  (server block ya incluido en [`services/web/nginx.conf`](../web/nginx.conf)).

## Integración con el dominio

1. **DNS** (la VM no sirve DNS; el DC mantiene la zona). Que
   `zabbix.sudoers.lan` resuelva al proxy `192.168.0.2`:
   ```bash
   sudo samba-tool dns add 192.168.0.2 sudoers.lan zabbix A 192.168.0.2 -U Administrator
   ```
2. **Monitorear dc1** (`192.168.0.2`): instalar `zabbix-agent2` NATIVO en dc1
   apuntando a `192.168.122.4` (`Server` y `ServerActive`). dc1 y la VM se ven
   directo por virbr0 (la VM consulta y responde sin salir a la LAN).
   En `server/nftables.conf` abrir el puerto del agente para la red NAT:
   ```
   tcp dport 10050 ip saddr 192.168.122.0/24 accept
   ```
3. **Monitorear clientes de la LAN**: agent pasivo en cada cliente; el server
   los consulta desde `192.168.0.2` (IP masquerada). Abrir en el firewall del
   cliente: `tcp dport 10050` con origen `192.168.0.2`. No usar modo activo
   desde la LAN: el cliente no puede iniciar conexión hacia la VM.
4. **Monitorear la VM misma** (métricas reales del SO): instalar
   `zabbix-agent2` nativo en la VM apuntando a `localhost` (el contenedor
   `zabbix-agent` solo ve el contenedor).

## Notas

- Imágenes oficiales Zabbix 7.0 (`alpine-7.0-latest`) — pin en `.env`.
- DB password en `.env` de la VM (fuera del repo, no versionar).
- Alertas: configurar Media Type "Email" contra el Postfix del dominio
  (`mail.sudoers.lan`) cuando el correo esté activo.