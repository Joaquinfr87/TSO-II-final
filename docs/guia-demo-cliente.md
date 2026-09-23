# Guía de demo — Cliente unido al dominio (presentación)

Secuencia de comandos para mostrar **desde el cliente** durante la
presentación de la Actividad 7. Supone una VM/estación Debian **ya unida** al
dominio (`realm join`), con SSSD instalado y DNS apuntando al DC
(`192.168.0.2`).

> Equivalente del lado servidor: `docs/presentacion.md`. Capturas e informe:
> `docs/latex/a7/`.

---

## 1. Red y DNS del cliente

**Muestra:** la IP y que DNS/dominio llegan por DHCP (Kea), sin configurar
nada a mano.

```bash
ip -4 -br a
nmcli device show enp1s0 | grep -iE 'IP4.DNS|IP4.DOMAIN'
# debe dar: 192.168.0.2  y  sudoers.lan
```

## 2. Descubrimiento del dominio

**Muestra:** el cliente encuentra al DC solo con los SRV del DNS → por eso el
DC es el DNS autoritativo.

```bash
sudo realm discover sudoers.lan
```

```text
sudoers.lan
  type: kerberos
  realm-name: SUDOERS.LAN
  configured: yes
  server-software: samba
  client-software: sssd
  required-package: oddjob-mkhomedir ...
  login-formats: %U
  login-policy: allow-realm-logins
```

> `realm` está en `/usr/sbin/` → usarlo con `sudo` (o ruta completa).

## 3. Identidades del AD visibles desde el cliente

**Muestra:** SSSD consulta al AD en vivo, sin cuentas duplicadas en cada
máquina.

```bash
getent passwd david nicolas          # UID 10000+ → del AD
getent group 'admins'
getent group 'Domain Admins'
```

> Ojo con `joaquin` en la demo: la VM tiene un **usuario local con el mismo
> nombre** y tapa al del AD (el NSS lo encuentra primero). Usar `david`,
> `nicolas` o un usuario de prueba (`juan`/`demo`).

## 4. Ticket Kerberos desde el cliente

**Muestra:** el TGT emitido por el DC (password nunca viaja por la red).

```bash
kinit juan@SUDOERS.LAN              # password del usuario de prueba
klist                                # krbtgt/SUDOERS.LAN@SUDOERS.LAN, vigencia 24h
kdestroy
```

> **Sin `sudo`:** si se usa `sudo`, el ticket queda en la caché de root y el
> `klist` del usuario da `No credentials cache found`.

## 5. Acceso a recursos SMB (cierre de la secuencia)

**Muestra:** el cliente solo aporta credenciales; los permisos los decide el
servidor por grupos AD.

```bash
kinit juan@SUDOERS.LAN
gvfs-mount smb://dc1.sudoers.lan/home/juan
# o montaje CIFS:
sudo mount -t cifs //dc1.sudoers.lan/departamentos /mnt \
     -o username=juan,domain=SUDOERS,vers=3.0
ls /mnt
```

## 6. Bono: DHCP (solo si el cliente está en la LAN con cable)

**Muestra:** IP, DNS, dominio y NTP entregados de una sola vez por Kea.

```bash
sudo nmcli device disconnect enp1s0
sudo nmcli device connect enp1s0
ip -4 -br a                          # IP del pool .100-.199
nmcli device show enp1s0 | grep -iE 'IP4.DNS|IP4.DOMAIN'
```

---

## Orden sugerido en vivo

1. `realm discover` → el DNS descubre el dominio.
2. `getent passwd david nicolas` → identidades del AD en vivo.
3. `kinit` + `klist` → el TGT (la estrella).
4. `gvfs-mount` / `mount -t cifs` → recurso SMB con permisos AD.

Cerrar mostrando del **server** que el equipo apareció:

```bash
samba-tool computer list | grep -iE 'debian-prueba|nbk'
```

## Equivalencias Windows (contabilidad/marketing)

| Prueba | Linux (Debian) | Windows |
| --- | --- | --- |
| DNS | `nmcli device show enp1s0` | `Set-DnsClientServerAddress -InterfaceAlias "Ethernet" -ServerAddresses 192.168.0.2` |
| Descubrir DC | `realm discover` | `nltest /dsgetdc:sudoers.lan` |
| Unión | `sudo realm join -U administrator sudoers.lan` | `Add-Computer -DomainName "SUDOERS.LAN" -Credential (Get-Credential) -Restart` |
| Verificar | `getent passwd david` | `nltest /sc_verify:sudoers.lan` |
| Ticket | `kinit` + `klist` | `klist` |

---

## Trouble-shooting (lo que encontramos en el lab)

- `realm: Necessary packages are not installed: sssd ...` aunque estén
  instalados → falta `packagekit` (realmd lo usa para chequear los paquetes):
  `sudo apt install -y packagekit`.
- `kinit` con `sudo` → ticket en caché de root, `klist` da vacío. Usar siempre
  sin `sudo`.
- `realm: command not found` → el binario está en `/usr/sbin/`: usar `sudo
  realm ...` o `/usr/sbin/realm ...`.
- `dc1.sudoers.lan` resolvía a varias IPs (172.17.0.1, 172.18.0.1 = gateways de
  redes Docker; 192.168.100.39). Síntoma típico: `getent passwd david` / `id
  david` fallan ("no such user") aunque `realm list` y `dig` parezcan OK: SSSD
  prueba contra la primera de las IPs muertas y no llega al AD.
  → Fix **durable** en `/etc/samba/smb.conf` de `dc1` (`[global]`):
  ```ini
  interfaces = lo 192.168.0.2/32
  bind interfaces only = yes
  ```
  `systemctl restart samba-ad-dc` y luego borrar los A residuales con
  `samba-tool dns delete localhost sudoers.lan dc1 A 172.17.0.1 -U administrator`
  (ídem `172.18.0.1`). Verificar `dig dc1.sudoers.lan` → 1 solo A. En el
  cliente: `systemctl restart sssd` (purga caché negativa) y re-testear.
- `samba-tool dns query/delete` sin ticket ni credencial →
  `NT_STATUS_LOGON_FAILURE` o `WERR_ACCESS_DENIED`; usar `-U administrator` o
  `-k yes` con TGT, y que el usuario esté en *Domain Admins* (SI los `Admins`
  con permiso: agregarlos con `samba-tool group addmembers 'Domain Admins'`).
- `samba-tool dns query` desde `localhost`/`127.0.0.1` sin ticket →
  `NT_STATUS_LOGON_FAILURE`; usar `-U administrator` o `-k yes` con TGT.
- DNS en clientes: apuntar siempre a `192.168.0.2`; si la resolución viene de
  otro lado (p. ej. dnsmasq del NAT de una VM), forzarla con `nmcli`.