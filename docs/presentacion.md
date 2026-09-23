# Presentación — Pruebas de Samba en vivo

Guion de demo para la presentación (ítems del punto **4. Desarrollo del
Trabajo**). Cada etapa explica la **teoría en el momento** en que se ejecuta el
comando correspondiente. Se indica dónde corre: **server** (`dc1`,
192.168.0.2) o **cliente** de la LAN.

La idea: **capturar pantalla en cada bloque** y sostener con la salida en vivo
cada etapa del desarrollo.

---

## 1. Preparación del sistema — server

**Paso 1.1 — Identidad del host (hostname)**
```
hostnamectl status | head -3        # hostname = dc1
```

> **Teoría:** los clientes encuentran al DC por **nombre**. El hostname es la
> "matrícula" de la máquina en el dominio; si cambiara, los equipos que ya lo
> conocen lo perderían. Por eso fijamos `dc1` y nunca más se toca.

**Paso 1.2 — IP fija (y su registro en /etc/hosts)**
```
ip -4 a show eno1                    # 192.168.0.2/24
grep -E 'dc1|sudoers' /etc/hosts     # el DC resuelve por su IP, no por 127.0.0.1
```

> **Teoría:** un DC **no puede tener IP variable**: Kerberos y DNS lo
> referencian todo el tiempo por `192.168.0.2`. Además Samba exige que el
> hostname resuelva a su IP de LAN y **nunca a 127.0.0.1** — si resuelve a
> loopback, el DC se "habla a sí mismo" y los clientes no lo alcanzan.

**Paso 1.3 — Servicios del host**
```
systemctl is-enabled samba-ad-dc nftables chrony docker
```

> **Teoría:** este server "todo-en-uno" reúne varios roles: **DC** (Samba
> nativo), **firewall** (nftables), **NTP** (chrony, da la hora a la LAN) y
> **Docker** (los contenedores). Mostramos que todos quedan habilitados para
> arrancar con el boot, con el orden correcto.

## 2. Instalación y promoción del DC — server

**Paso 2.1 — El daemon del DC está activo y es el que arranca al boot**
```
systemctl is-active samba-ad-dc          # active
systemctl is-enabled samba-ad-dc         # arranca al boot
```

> **Teoría:** el DC no es "varios programas": es **un solo daemon**
> (`samba-ad-dc`) que habla todos los protocolos del AD a la vez (LDAP +
> Kerberos + SMB + DNS). Que esté `enabled` significa que el dominio vuelve a
> estar arriba solo tras un reinicio.

**Paso 2.2 — Nivel funcional del dominio**
```
samba-tool domain level show
```

> **Teoría:** el **functional level** es el "modo de compatibilidad" del AD:
> cuanto más alto, más funciones activas ofrece (la versión de "reglas" del
> dominio). Es una pista de que esto es un AD serio y no un archivo suelto.

**Paso 2.3 — Datos del dominio**
```
samba-tool domain info 127.0.0.1
```

> **Teoría:** acá se ven los *términos del contrato* AD:
> **Realm** = nombre DNS en mayúsculas (`SUDOERS.LAN`); **NetBIOS** = nombre
> corto legacy (`SUDOERS`); **Forest/Domain** = el árbol AD; y **básicamente
> el host y la IP** que actúan de punto de referencia. También confirma el rol
> `active directory domain controller` (¡la promoción funcionó!).

**Paso 2.4 — Los puertos del AD escuchando**
```
ss -ltn | grep -E ':88|:389|:445|:53'
```

> **Teoría:** cada puerto es un servicio del dominio: **53** DNS, **88**
> Kerberos, **389** LDAP, **445** SMB. Es la prueba física (de red) de que el
> DC está "abierto" para los clientes.

## 3. Configuración del DNS interno — server

**Paso 3.1 — Registro A del DC**
```
dig dc1.sudoers.lan
```

> **Teoría:** el AD **se apoya en DNS** para todo. Un registro **A** es la
> tabla nombre→IP: `dc1.sudoers.lan → 192.168.0.2`. Es lo primero que
> consulta cualquier cliente para llegar al dominio.

**Paso 3.2 — Registros SRV (descubrimiento automático)**
```
dig _ldap._tcp.dc._msdcs.sudoers.lan SRV
```

> **Teoría:** los registros **SRV** son las "guías de servicios" del dominio:
> le dicen a cualquier cliente *dónde está* el LDAP, el Kerberos, el DC, etc.
> **Sin configuración manual** el cliente descubre todo. Si estos SRV no
> existen o no responden → los clientes no encuentran el DC → no hay dominio.
> Es el motivo por el cual el DC debe ser DNS autoritativo.

**Paso 3.3 — Subdominios de servicios y miembros**
```
dig joaquin.sudoers.lan
dig web.sudoers.lan
```

> **Teoría:** además de la infraestructura, la zona guarda direcciones
> "lindas" apuntando al mismo server: cada miembro (`joaquin.`, `david.`,
> `nicolas.`) y cada servicio web (`web.`, `print.`, `portainer.`). Todo
> resuelve centralizado en el DC (DNS = 192.168.0.2).

**Paso 3.4 — Ver la zona completa**
```
samba-tool dns query 127.0.0.1 sudoers.lan @ ALL
```

> **Teoría:** el DC de Samba mantiene su DNS con el backend **SAMBA_INTERNAL**
> (auto-gestionado, sin efecto en Bind9 como en el lab) y usa un *forwarder*
> al router para resolver nombres externos. Acá se listan todos los registros
> de la zona de una.

## 4. Creación de usuarios y grupos — server

**Paso 4.1 — Grupos de seguridad**
```
samba-tool group list | grep -E 'admins|sistemas|srv-|oficina'
```

> **Teoría:** los permisos se otorgan a **grupos**, no a personas sueltas:
> por eso el "quién puede qué" se administra en un solo lugar. Tenemos
> `admins`/`sistemas` (mando técnico), `srv-files` (archivos), `srv-dba`
> (base de datos), `srv-mail`, `contabilidad`, `marketing`, `oficina`.

**Paso 4.2 — Usuarios del dominio**
```
samba-tool user list
```

> **Teoría:** los usuarios son **objetos** dentro de un árbol LDAP, no
> cuentas sueltas en cada máquina. Un cambio de password o de grupo se
> propaga a toda la organización automáticamente.

**Paso 4.3 — Detalle de un usuario (y sus grupos)**
```
samba-tool user show joaquin
```

> **Teoría:** cada objeto tiene un **sAMAccountName** (login corto usás al
> entrar), un **UPN** (`joaquin@SUDOERS.LAN`) y pertenece a *n* grupos. Quien
> está en varios grupos **hereda** la suma de permisos (ej. `joaquin` →
> `admins` + `sistemas` + `srv-files`).

**Paso 4.4 — (opcional en vivo) Alta de un usuario**
```
samba-tool group addmembers 'sistemas' juan
```
> **Teoría:** el alta/baja se resuelve en **minutos y sin tocar máquinas**:
> creás el objeto y lo metés al grupo. La herramienta usada es
> `dc/add-users-groups.sh` (idempotente).

## 5. Pruebas de autenticación — server y cliente

**Paso 5.1 — Pedir ticket en el server (Kerberos)**
```
kinit juan@SUDOERS.LAN      # password → OK
klist                       # ticket emitido por dc1.sudoers.lan
kdestroy
```

> **Teoría (Kerberos):** el problema que resuelve es *"demostrar quién soy
> sin mandar la contraseña por la red"*. La respuesta son **tickets**: el KDC
> (el DC) emite un **TGT** (llave maestra) al hacer login — `kinit` lo pide,
> `klist` lo muestra (emisor y vigencia), `kdestroy` lo descarta. El ticket va
> **firmado** por el DC: nadie puede falsificar una identidad.

**Paso 5.2 — Autenticar desde un cliente real**
```
kinit juan@SUDOERS.LAN && klist     # login kerberos desde el cliente
ssh juan@dc1.sudoers.lan                 # (si el usuario tiene acceso)
```

> Sin `sudo` en `kinit`: si se usa `sudo`, el ticket queda en la caché de
> root y el `klist` del usuario da `No credentials cache found`.

> **Teoría:** la misma cuenta, el mismo "carnet", funciona **desde cualquier
> equipo de la red** porque es el DC quien emite los tickets. Esto es el
> *single sign-on*: te identificás una vez y accedés a todo.

## 6. Unión de clientes al dominio — cliente (+ server de confirmación)

**Paso 6.1 — El join en el cliente Debian**
```
sudo realm join --user=administrator SUDOERS.LAN
```

> **Teoría del join:** unirse es más que poner DNS. `realm join` crea una
> **computer account** en el AD: el equipo pasa a ser un objeto del dominio,
> con su propio secreto de máquina. Desde ese momento el cliente usa el AD
> como fuente de identidad (LDAP para leer, Kerberos para autenticar), sin
> copiar usuarios locales. En Windows ocurre idéntico con el canal seguro.

**Paso 6.2 — El cliente "ve" a los usuarios del AD**
```
getent passwd joaquin david nicolas
getent group 'admins'
```

> **Teoría:** `getent` resuelve contra el AD → los usuarios del dominio
> aparecen como si fueran locales (por SSSD). Nadie está "duplicado" en cada
> notebook: se consultan en vivo al DC.

**Paso 6.3 — Confirmación desde el server**
```
samba-tool computer list
```

> **Teoría:** el DC registra a la notebook como equipo del dominio. La demo
> "redonda": del lado del cliente unimos, del lado del server lo vemos
> aparecer en el AD.

## 7. Recursos de archivo (SMB) — server y cliente

**Paso 7.1 — Listar los shares contra el DC (server)**
```
smbclient -L dc1 --user=joaquin          # lista shares
smbclient //dc1/homes --user=joaquin     # abrir un recurso
```

> **Teoría:** SMB/CIFS (puerto 445) es el protocolo de archivos de red. El DC
> sirve shares **nativos** (sin contenedor): `departamentos`, `homes` (cada
> usuario ve **su propio** directorio) y `respaldo`.

**Paso 7.2 — El cliente monta/abre el recurso**
```
kinit joaquin@SUDOERS.LAN
gvfs-mount smb://dc1.sudoers.lan/home/joaquin   # o: sudo mount -t cifs
# navegar /srv/samba/departamentos desde el cliente
```

> **Teoría:** los **permisos se definen por grupos AD en el servidor** — quien
> está en `srv-files`/`admins`/`sistemas` accede, quien no, no puede ni
> listar. El cliente solo aporta sus credenciales del dominio, sin claves
> locales.

## 8. Bono: DHCP + DNS en vivo (si alcanza el tiempo)

**Paso 8.1 — El server asignando IPs (Kea)**
```
docker compose ps
sudo ss -ulnp | grep ':67 '          # Kea escuchando en 192.168.0.2
sudo cat /var/lib/kea/kea-leases4.csv   # concesiones en vivo
```

> **Teoría:** DHCP (67/udp) asigna IPs automáticamente. Kea corre en contenedor
> con `network_mode: host` (porque DHCP usa broadcast y no atraviesa un
> bridge de Docker) y es **la única fuente de IPs** (el DHCP del router
> TP-Link está apagado). Además tiene **reservas por MAC** para los equipos
> admin (`.50–.52`): siempre la misma máquina → la misma IP.

**Paso 8.2 — Un cliente toma IP y llega "con todo"
```
sudo dhclient -v enoX                # toma IP del pool .100-.199
ip -4 a                              # IP, DNS=192.168.0.2, dominio, gateway
dig dc1.sudoers.lan                  # usa el DNS entregado por DHCP
```

> **Teoría:** DHCP no entrega *solo* una IP: Kea reparte también las
> **opciones** que hacen encajar la red sin tocar nada a mano — DNS =
> `192.168.0.2`, dominio = `sudoers.lan`, gateway = router, NTP =
> `192.168.0.2`. Por eso un equipo recién conectado queda "listo para el
> dominio" en segundos.

---

## Resumen rápido server vs cliente

| Etapa | Server (dc1) | Cliente unido |
| --- | --- | --- |
| Preparación (hostname, IP) | ✅ | — |
| Instalación / promoción DC | ✅ | — |
| DNS interno | ✅ (`dig`, `samba-tool dns`) | ❌ opcional: `dig` con DNS 192.168.0.2 |
| Usuarios y grupos | ✅ (`samba-tool`) | ❌ opcional: `getent` |
| Autenticación Kerberos | ✅ (`kinit`/`klist`) | ✅ `kinit` desde el cliente |
| Unión al dominio | ❌ confirmar con `samba-tool computer list` | ✅ **`realm join` + `getent`** |
| Recursos SMB | ✅ `smbclient` contra el DC | ✅ montar/abrir share |
| DHCP (Kea) | ✅ leases + ss | ✅ `dhclient` + `ip a` |

## Versión Windows (equipos de contabilidad/marketing)

La mayoría de la red es Linux, pero las 3 pruebas clave también se pueden
hacer con un equipo **Windows 10/11** unido al dominio (los puertos AD/RPC y
NetBIOS ya están abiertos en `server/nftables.conf`). Equivalencias:

| Etapa | Linux (Debian) | Windows |
| --- | --- | --- |
| Unión al dominio | `realm join sudoers.lan` + `adminpass` | `netdom join %computername% /domain:sudoers.lan /userd:administrator` (o GUI: Sistema → Cambiar PC → dominio `sudoers.lan`) |
| Verificar unión | `samba-tool computer list` | `nltest /sc_verify:sudoers.lan` |
| Ver DC | `dig dc1.sudoers.lan` | `nltest /dsgetdc:sudoers.lan` |
| DNS | `dig dc1.sudoers.lan` | `nslookup dc1.sudoers.lan` |
| Autenticación Kerberos | `kinit` + `klist` | `klist` (incluido en Windows) tras `runas /netonly` o login |
| Recursos SMB | `gvfs-mount` / `mount -t cifs` | `net use Z: \\dc1.sudoers.lan\departamentos /user:SUDOERS\joaquin` |
| DHCP | `dhclient -v` + `ip a` | `ipconfig /release` + `ipconfig /renew` + `ipconfig /all` |

Detalles de Windows a tener en cuenta en la demo:

- El cliente Windows debe tener DNS configurado a **192.168.0.2** (si tomó IP
  por DHCP del server, ya llega solo) y el sufijo de DNS `sudoers.lan`.
- Para `netdom`/`nltest` correr una terminal como Administrador.
- El join pide el usuario administrador del dominio: `SUDOERS\administrator`.
- Tras unir, `nltest /dclist:sudoers.lan` lista el DC y `nltest /sc_query`
  confirma el canal seguro.
- Windows usa el puerto RPC dinámico (`49152–65535`) que ya está permitido.

## Preparación del cliente de demo (Linux/Debian)

La notebook demo necesita paquetes; cada comando usado en este guion viene de
uno de estos:

| Paquete | Comandos que habilita |
| --- | --- |
| `realmd` + `adcli` | `realm join` |
| `sssd` | `getent` de usuarios/grupos AD |
| `krb5-user` | `kinit`, `klist`, `kdestroy` |
| `dnsutils` (o `bind9-dnsutils` en trixie) | `dig`, `nslookup` |
| `cifs-utils` | `mount -t cifs` / `gvfs-mount` |
| `smbclient` | `smbclient` (opcional en cliente) |
| `isc-dhcp-client` | `dhclient -v` (si la notebook usa NetworkManager, el binario no viene) |

Instalación completa de la notebook:

```bash
sudo apt update
sudo apt install realmd adcli sssd krb5-user dnsutils cifs-utils smbclient
```

> En el server (`dc1`) ya están instalados por `dc/provision.sh`
> (`krb5-user`, `dnsutils`, `smbclient`, …) — la lista de arriba es solo para
> **el cliente** que se une en la demo.

## Notas para la demo

- Usar un **usuario de prueba** con password conocida para no exponer las
  reales: `sudo samba-tool user create demo Presentacion!2026`.
- Prever **una notebook cliente** preconfigurada (nombre corto, sin conflictos
  con las reservas DHCP).
- Tener `ca.crt` y el proxy HTTPS a mano si se muestra el portal web
  (`services/web/tls/`).
- Capturar salida de consola en cada bloque; si algo falla en vivo, mostrar
  `journalctl -u samba-ad-dc -f` o `docker compose logs dhcp` como diagnóstico.