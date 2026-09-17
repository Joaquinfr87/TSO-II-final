# server/ — Configuración del host (fuera de Docker)

Acá vive la configuración del **sistema operativo** del servidor físico: lo
que corre nativo (firewall, SSH, NTP) más el `deploy.sh`. Todo se versiona y
se aplica desde el repo; nadie toca el server a mano.

## Estructura

```text
server/
├── README.md        ← este archivo
├── nftables.conf    ← firewall red única 192.168.0.0/24 (política drop)
├── sshd_config      ← SSH endurecido (solo claves, solo admins)
├── chrony.conf      ← NTP de la red (los clientes sincronizan contra el DC)
└── deploy.sh        ← valida y aplica los configs de forma segura
```

## Flujo de trabajo

```bash
# en el server (repo clonado):
git pull
sudo bash server/deploy.sh
```

El script **valida la sintaxis** antes de aplicar (`nft -c`, `sshd -t`),
**respalda** los configs previos y si algo falla no deja el server sin
conexión.

### Rollback

```bash
sudo nft flush table inet filter && sudo nft -f /etc/nftables.conf   # firewall
sudo cp /etc/ssh/sshd_config.bak.<ts> /etc/ssh/sshd_config && sudo systemctl restart ssh
sudo cp /etc/chrony/chrony.conf.bak.<ts> /etc/chrony/chrony.conf && sudo systemctl restart chrony
```

## Notas

1. El firewall es para **una sola red** `192.168.0.0/24`. Los puertos de
   administración (22, 9443, 5432) se restringen a `admin_ips` (completar en
   `nftables.conf`).
2. Kea (DHCP) usa `network_mode: host` → entra por el puerto 67/udp directo.
3. No usar `flush ruleset` global: rompe las cadenas de Docker.
4. **Antes** de activar SSH sin password: subir las claves con `ssh-copy-id`.
5. Sin secretos en el repo: claves privadas, tokens o passwords nunca acá.

## Interacción con el DC

- El host y el DC son la **misma máquina** (`dc1.sudoers.lan` / 192.168.0.10).
- Chrony del host = NTP que sirve el DC (Kerberos exige reloj sincronizado).
- Puertos del DC nativo (53, 88, 389, 445, 139) quedan abiertos solo a la LAN
  en este firewall; los contenedores no los re-publican.