# TSO-II-final — Infraestructura IT (Linux)

Infraestructura IT de la organización sobre **una sola máquina Debian**:
**AD DC con Samba 4** (nativo, fuera de Docker) + el resto de servicios en
**contenedores Docker** (heredados del lab `TSO-II`). Clientes Linux
(SSSD + AD) con unas pocas Windows para contabilidad/marketing.

Red: **una sola red `192.168.0.0/24`** — server `192.168.0.2`, gateway router `192.168.0.1`

## Documentación

**Toda la documentación vive en [`docs/`](docs/README.md).**

- **[`docs/arquitectura.md`](docs/arquitectura.md)** — diseño completo (la leés primero).
- **[`AGENTS.md`](AGENTS.md)** — contexto resumido para agentes de IA.

## Arranque rápido

```bash
cp .env.example .env        # completar valores
docker compose up -d --build
```

## Repos relacionados

- [`../TSO-II`](../TSO-II) — laboratorio original (servicios base: dhcp, mail, web, database, print, portainer).