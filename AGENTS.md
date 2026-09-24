# AGENTS.md — Contexto para agentes de IA

> Resumen ejecutivo del proyecto. Si necesitás profundizar, leé
> [`docs/arquitectura.md`](docs/arquitectura.md) — es la fuente de verdad.

## Qué es este repo

Infraestructura IT de una organización, **100% Linux**, sobre una **sola
máquina Debian** ("laptop siempre encendida", estilo lab). Es la evolución
"empresarial" del laboratorio del repo hermano `../TSO-II`.

- **AD DC = Samba 4, NATIVO** (fuera de Docker) → carpeta `dc/`.
- **Resto de servicios = contenedores Docker** (docker-compose), heredados y
  adaptados del lab → `services/` + `docker-compose.yml`.
- **Clientes**: Linux (mayoría) + unas pocas **Windows** solo para
  contabilidad/marketing. Todos unidos al dominio AD.

## Datos de red (IMPORTANTE)

- **UNA sola red plana:** `192.168.0.0/24`. La antigua `192.168.20.0/24` del
  lab quedó **descartada** (no hay control sobre esa red).
- **Router:** TP-Link **TL-WR850N v3** (Hardware Ver. `00000002`, firmware
  3.16.0), IP `192.168.0.1`, maneja la red y es la puerta de enlace. Su DHCP
  **se desactiva** cuando Kea tome el servicio (evita DHCP doble).
- **Server / DC:** ip fija **`192.168.0.2`** (conectado **por cable** al
  router), hostname `dc1` → `dc1.sudoers.lan`. La IP `192.168.0.10` del
  diseño original quedó descartada.
- **DHCP (Kea):** pool dinámico `192.168.0.100–199`; reservas `.1–.49`
  infraestructura, `.50–.99` equipos fijos (impresoras, PCs admin, cajas).
  Entrega como **DNS = 192.168.0.2**, dominio `sudoers.lan`, gateway
  `192.168.0.1`, NTP `192.168.0.2`.
- **Reservas por MAC:** se configuran en `.env` → `DHCP_RESERVATIONS`
  (formato `"MAC=IP=hostname;…"`), que el entrypoint de Kea convierte a
  reservas del subnet. Los PCs de los admins ocupan `.50–.52` (coincide con
  `admin_ips` del firewall).
- **AD:** dominio/realm `SUDOERS.LAN`, NetBIOS `SUDOERS`, Kerberos realm `SUDOERS.LAN`.

## Máquinas

- **dc1** = `192.168.0.2` — el host físico (DC Samba + Docker + resto). Es la
  única máquina "real"; el resto son VMs/equipos que le cuelgan.
- **VM Zabbix** = `192.168.122.4` — máquina virtual en dc1 (libvirt/KVM), red
  **NAT** `192.168.122.0/24` (virbr0). Único rol: **Zabbix server + web UI**
  (monitoreo). No hay bridge en el host, así que NAT es la única opción.
  ATENCIÓN (consecuencia del NAT): ninguna máquina de la LAN puede iniciar
  conexión hacia `192.168.122.4`. Se publica SOLO vía el proxy inverso como
  `zabbix.sudoers.lan` → `192.168.122.4` (mismo patrón que david/nicolas).
  El monitoreo en sentido inverso no tiene problema: la VM sale por la red del
  host (con agents en **modo activo**, que empujan hacia el server, no hace
  falta abrir puertos entrantes en los clientes).
- **Equipos de admins:** `pc-joaquin .50`, `pc-david .51`, `pc-nicolas .52`
  (fijos, `.50–.99`); usuarios dinámicos en `.100–.199`.

## Usuarios (AD)

- **Admins:** `joaquin`, `nicolas`, `david` (grupo `admins` + `sistemas`).
- **Usuarios de prueba:** `grupo2`, `grupo3`, …, `grupo9` (grupo `oficina`).
  Se crean con `dc/add-users-groups.sh`, idempotente.
- **`tsoII`:** usuario nuevo para pruebas de logon script en Windows — cambia
  el wallpaper vía `scriptPath` de AD (script `tsoII-wallpaper.cmd` en netlogon).

## Reglas técnicas que NO se negocian

1. **El DC de Samba corre NATIVO, nunca en contenedor** (frágil; decisión ya
   documentada en el lab `services/domain/README.md`).
2. **DNS autoritativo del dominio lo maneja el DC** (zona AD + SRV). El
   Bind9 del lab se retira/adapta; no compite con la zona `sudoers.lan`.
3. **Kea requiere `network_mode: host`** en Docker: BOOTP/DHCP usa broadcast
   `67/udp` y no funciona mapeado a través de un bridge.
4. **Puertos del DC NO se re-publican en contenedores:** `53`, `88`, `389`,
   `445`, `139` (+ `636` LDAPS opcional). Son del DC nativo.
5. **Sin secretos en git:** `.env` ignorado; en el repo solo `.env.example`.
6. **Un solo `docker-compose.yml`** en la raíz declara todos los servicios.

## Servicios (resumen)

| Servicio | Cómo | Dónde |
| --- | --- | --- |
| AD DC (identidad: Kerberos+LDAP+DNS+SMB) | Samba 4 | NATIVO (`dc/`) |
| NTP | chrony | NATIVO |
| Firewall / SSH | nftables / sshd endurecido | NATIVO (`server/`) |
| DHCP | Kea | CONTENEDOR (`services/dhcp`, host network) |
| Correo | Postfix + Dovecot (auth LDAP AD) | CONTENEDOR (`services/mail`) |
| Webmail | Roundcube | CONTENEDOR |
| Archivos | Shares SMB del DC (perms por grupos AD) | NATIVO (smb.conf del DC) |
| Web/Proxy inverso | Nginx `*.sudoers.lan` + TLS | CONTENEDOR (`services/web`) |
| Base de datos | PostgreSQL (+MariaDB si hace falta) | CONTENEDOR (`services/database`) |
| Impresión | CUPS | CONTENEDOR (`services/print`) |
| Gestión Docker | Portainer | CONTENEDOR |
| Monitoreo | Zabbix (server + web; agents en hosts) | VM `192.168.122.4` — `services/zabbix` (compose propio) |
| Backup | restic/borg | NATIVO cron |

## Estructura del repo

```text
TSO-II-final/
├── AGENTS.md            ← este archivo (contexto para IA)
├── docker-compose.yml   ← servicios contenedor (fuente de verdad)
├── .env.example
├── README.md            ← índice corto → docs/
├── dc/                  ← Samba AD DC nativo (provision.sh, shares.conf, krb5, scripts)
├── server/              ← host: nftables, sshd, chrony, deploy
├── clients/             ← guías para unir clientes Linux/Windows al dominio (pendiente)
├── services/            ← por servicio contenedor (dhcp, web, mail, db, print; webmail/monitoring/apps pendientes)
└── docs/                ← TODA la documentación (arquitectura, futuro: red, seguridad, backup…)

Máquinas: dc1 (host físico, 192.168.0.2) + VM Zabbix (192.168.122.4, NAT).
```

## Flujo de trabajo habitual

```bash
cp .env.example .env
docker compose up -d --build            # levantar/actualizar servicios
docker compose up -d <servicio>         # servicio puntual
```

- Documentación nueva va SIEMPRE en `docs/` (no inflar el `README.md`).
- Un servicio nuevo = carpeta `services/<nombre>` + bloque en el compose.
- En el server físico: `git pull && sudo bash server/deploy.sh` (no tocar a mano).

## Documentación detallada

- [`docs/arquitectura.md`](docs/arquitectura.md) — diseño completo, plan IP,
  fases de implementación (Fase 0→6) y limitaciones.
- [`docs/README.md`](docs/README.md) — índice de documentación.
- Laboratorio original: `../TSO-II` (servicios base y decisiones).