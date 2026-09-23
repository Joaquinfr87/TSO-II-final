# Guia de Capturas de Pantalla — Controlador de Dominio (Actividad 7)

Todas las capturas se guardan en `latex/a7/figuras/` (es decir,
`docs/latex/a7/figuras/`). El PDF las muestra automáticamente al compilar.
Si una captura falta, el PDF deja un marco vacío con el pie de figura.

Los comandos corren en **dc1** (`192.168.0.2`) salvo que se indique
"CLIENTE".

---

## 1. Identidad del host (hostname)

**Archivo:** `captura-hostname.png`
**Comando (server):**
```bash
hostnamectl status | head -3
```
**Qué mostrar:** `Static hostname: dc1`.

---

## 2. IP fija y /etc/hosts

**Archivo:** `captura-ip-fija.png`
**Comando (server):**
```bash
ip -4 a show eno1
grep -E 'dc1|sudoers' /etc/hosts
```
**Qué mostrar:** `inet 192.168.0.2/24` y la línea
`192.168.0.2   dc1.sudoers.lan   dc1`.

---

## 3. Servicios del host habilitados

**Archivo:** `captura-servicios-host.png`
**Comando (server):**
```bash
systemctl is-enabled samba-ad-dc nftables chrony docker
```
**Qué mostrar:** los 4 servicios en estado `enabled`.

---

## 4. Instalación de Samba

**Archivo:** `captura-samba-install.png` (opcional)
**Comando (server):**
```bash
apt install -y samba smbclient winbind krb5-user
samba --version
```
**Qué mostrar:** el final de la instalación y la versión de Samba 4.

---

## 5. Promoción del DC / datos del dominio

**Archivo:** `captura-domain-info.png`

Son **dos comandos distintos**, uno para cada pregunta:

### Comando A — "¿Con qué reglas corre el dominio?"
```
samba-tool domain level show
```
Este muestra el **nivel funcional** (functional level): el "modo de
compatibilidad" del AD. Es la versión de las *reglas* del dominio; cuanto más
alto, más funciones activas ofrece.
```
Domain: SUDOERS
Domain level: 2008 R2
Forest level: 2008 R2
```

### Comando B — "¿Dónde está el DC y a qué dominio sirve?"
```
samba-tool domain info 127.0.0.1
```
Este pregunta al DC (por loopback) quién es y qué confirma el rol de
authority. La línea que **prueba que la promoción funcionó** es la última:
`Server role: active directory domain controller`.
```
Domain:           SUDOERS
Domain SID:       S-1-5-21-...
Forest:           SUDOERS.LAN
Number of users:  13
Server role:      active directory domain controller      ← acá
```

En una sola captura: ejecutá el A, esperá la salida, y después el B (mostrá
la salida completa en la terminal).

> No vuelvas a correr `samba-tool domain provision` (destruiría el dominio).
> Esta captura y las siguientes son la prueba de que la promoción funcionó.

---

## 6. Puertos del dominio escuchando

**Archivo:** `captura-puertos-ad.png`
**Comando (server):**
```bash
ss -ltn | grep -E ':53|:88|:389|:445'
```
**Qué mostrar:** los 4 puertos (53 DNS, 88 Kerberos, 389 LDAP, 445 SMB)
a la escucha.

---

## 7. Registro A del DC

**Archivo:** `captura-dig-dc.png`
**Comando (server):**
```bash
dig dc1.sudoers.lan
```
**Qué mostrar:** la sección ANSWER con `dc1.sudoers.lan. ... A 192.168.0.2`.

---

## 8. Registros SRV de descubrimiento

**Archivo:** `captura-dig-srv.png`
**Comando (server):**
```bash
dig _ldap._tcp.dc._msdcs.sudoers.lan SRV
```
**Qué mostrar:** el registro SRV apuntando al puerto 389 de
`dc1.sudoers.lan`.

---

## 9. Zona DNS completa

**Archivo:** `captura-zona-dns.png`

Este comando **se autentica** contra el RPC del DC (no es de solo lectura
libre): primero sacás un ticket Kerberos y después consultás con `-k yes`.

**Comando A (server):**
```bash
kinit joaquin@SUDOERS.LAN        # te pide la password del dominio
```
**Comando B (server):**
```bash
samba-tool dns query dc1.sudoers.lan sudoers.lan @ ALL -k yes
```
> Si uso `127.0.0.1` sin ticket da `NT_STATUS_LOGON_FAILURE` — el error es de
> autenticación, no de la zona. Alternativa: `... -U administrator` (pide
> password).

**Qué mostrar:** los registros A de `dc1`, `web`, `joaquin`, etc. (puede
tomarse con scroll y mostrar unas líneas).

---

## 10. Grupos de seguridad

**Archivo:** `captura-grupos.png`
**Comando (server):**
```bash
samba-tool group list | grep -E 'admins|sistemas|oficina|contabilidad'
```
**Qué mostrar:** al menos `admins`, `sistemas` y `oficina`.

---

## 11. Usuarios del dominio

**Archivo:** `captura-usuarios.png`
**Comando (server):**
```bash
samba-tool user list
```
**Qué mostrar:** `joaquin`, `nicolas`, `david`, `grupo2` ... `grupo9`.

---

## 12. Detalle de un usuario

**Archivo:** `captura-user-show.png`
**Comando (server):**
```bash
samba-tool user show joaquin
```
**Qué mostrar:** `sAMAccountName`, `userPrincipalName` y el atributo
`memberOf` con los grupos.

---

## 13. Ticket Kerberos en el server

**Archivo:** `captura-kinit-klist.png`
**Comando (server):**
```bash
kinit juan@SUDOERS.LAN      # usa un usuario de prueba (demo)
klist
kdestroy
```
**Qué mostrar:** `klist` con el TGT emitido por `krbtgt/SUDOERS.LAN` y su
vigencia.

---

## 14. Ticket Kerberos en el cliente

**Archivo:** `captura-kinit-cliente.png`
**Comando (CLIENTE unido):**
```bash
kinit juan@SUDOERS.LAN && klist
```
> Sin `sudo`: hacer `kinit` con `sudo` guarda el ticket en la caché de root
> y el `klist` del usuario no lo encuentra (`No credentials cache found`).
**Qué mostrar:** el `klist` del cliente mostrando el ticket obtenido contra
el DC.

---

## 15. Unión del cliente (realm join)

**Archivo:** `captura-realm-join.png`
**Comando (CLIENTE):**
```bash
sudo realm join --user=administrator SUDOERS.LAN
```
**Qué mostrar:** el `Password for administrator:` y el retorno a la shell
sin errores.

---

## 16. getent en el cliente

**Archivo:** `captura-getent.png`
**Comando (CLIENTE):**
```bash
getent passwd joaquin david nicolas
getent group 'admins'
```
**Qué mostrar:** los usuarios resueltos desde el AD (UID >= 10000) y el
grupo `admins` con sus miembros.

---

## 17. Estaciones registradas en el AD

**Archivo:** `captura-computer-list.png`
**Comando (server):**
```bash
samba-tool computer list
```
**Qué mostrar:** el nombre del equipo del cliente unido (ej. `DESKTOP-NBK1$`).

---

## 18. Recursos compartidos del DC

**Archivo:** `captura-smbclient.png`
**Comando (server):**
```bash
smbclient -L dc1 --user=joaquin
```
**Qué mostrar:** la lista de shares (`departamentos`, `homes`, `respaldo`).

---

## 19. Kea escuchando y concesiones

**Archivo:** `captura-kea-ss.png`
**Comando (server):**
```bash
sudo ss -ulnp | grep ':67 '
sudo cat /var/lib/kea/kea-leases4.csv
```
**Qué mostrar:** Kea en `192.168.0.2:67` y algunas concesiones del pool.

---

## 20. Cliente tomando IP por DHCP

**Archivo:** `captura-dhclient.png`
**Comando (CLIENTE, si alcanza el tiempo):**
```bash
sudo dhclient -v enoX
ip -4 a
dig dc1.sudoers.lan
```
**Qué mostrar:** el handshake DHCP (DISCOVER/OFFER/ACK desde 192.168.0.2) y
la IP del pool dinámico (100–199) resolviendo `dc1.sudoers.lan`.

---

## Consejos generales

- Usa **ctrl+shift+s** (GNOME), **scrot** o **flameshot** para captura
  selectiva.
- Si salió texto corrupto de tildes, es solo la terminal: no afecta al PDF.
- Tomar "ventana" (no pantalla completa) para que las capturas se lean bien
  en el ancho del PDF.
- Las que se marcan "(opcional)" pueden omitirse sin romper el documento.