# dc/ — Samba 4 AD DC (nativo, fuera de Docker)

Controlador de dominio con **Samba 4** corriendo **nativo** sobre Debian.
Es el centro de identidad de toda la infraestructura: Kerberos + LDAP + DNS
autoritativo de `sudoers.lan` + recursos SMB.

> Un DC de Samba **no** corre en contenedor (frágil). Esta decisión quedó
> documentada en el lab: `TSO-II/services/domain/README.md`.

## Estructura

```text
dc/
├── README.md            ← este archivo
├── provision.sh         ← instala y provisiona el DC (samba-tool domain provision)
├── shares.conf          ← recursos de archivo AD ([departamentos], [homes], [respaldo])
├── krb5.conf            ← modelo de /etc/krb5.conf (lo genera provision.sh)
├── add-users-groups.sh  ← grupos y usuarios de la organización (idempotente)
├── dns-records.sh       ← registros A de servicios (proxy; Zabbix directo, idempotente)
└── password-policy.sh   ← política de contraseñas del dominio
```

## Requisitos previos (Fase 0)

- Debian instalado con **IP fija** `192.168.0.2` y **hostname `dc1`**.
- `/etc/hosts` debe mapear `dc1.sudoers.lan → 192.168.0.2` (NUNCA a 127.0.0.1).
- nftables + sshd endurecidos aplicados (`server/`).
- El **router** no debe ocupar puertos del DC (53/88/389/445/139/636).

## Bootstrap (Fase 1)

```bash
sudo bash dc/provision.sh
# adminpass: dc1? En producción pasar:
#   ADMIN_PASS='...' sudo bash dc/provision.sh

sudo bash dc/add-users-groups.sh   # grupos + usuarios AD
sudo bash dc/dns-records.sh        # registros A de servicios publicados
sudo bash dc/password-policy.sh    # hardening de contraseñas
```

`provision.sh` hace: hostname/hosts → instala samba+krb5+chrony → escribe
`/etc/krb5.conf` → `samba-tool domain provision` (realm SUDOERS.LAN, DNS
SAMBA_INTERNAL) → copia `shares.conf` e incluye el recurso → activa el
servicio `samba` (deshabilita smbd/nmbd/winbind, los maneja el dc).

## Verificación

```bash
sudo kinit administrator        # ticket Kerberos
sudo klist                      # ver ticket
smbclient -L localhost -U administrator   # listar shares
dig @localhost sudoers.lan      # DNS AD respondiendo (SRV)
samba-tool domain level show    # nivel funcional del dominio
```

## Recursos de archivo (shares.conf)

| Recurso | Path | Quién entra |
| --- | --- | --- |
| `[departamentos]` | `/srv/samba/departamentos` | `srv-files`, `sistemas`, `admins` |
| `[homes]` | `/srv/samba/homes/%U` | el propio usuario (`%S`) |
| `[respaldo]` | `/srv/samba/respaldo` | `srv-files`, `sistemas`, `admins` |

Los permisos se dan por **grupos AD**. Para carpetas por departamento se
crean subcarpetas dentro de `[departamentos]` y se setean ACL con
`smbcacls`/Explorador. Los homes se crean automáticamente con
`pam_mkhomedir` cuando el cliente Linux entra (ver `clients/`).

## Notas técnicas (no negociar)

- **Puertos del DC** (53, 88, 389, 445, 139, 636) no se re-publican en
  contenedores. No hay `services/dns` ni `services/files`: DNS y SMB los da el DC.
- El DC **es DNS** → los clientes apuntan a `192.168.0.2` (lo entrega Kea).
- NTP: el mismo host corre **chrony** (`server/chrony.conf`); los clientes
  sincronizan contra él.
- GPO: Samba soporta un subconjunto; no es un AD de Windows completo.

## Estado

- [ ] Fase 0 (base del server) lista
- [ ] Fase 1: DC provisionado
- [ ] Fase 3: ACLs por departamento definidas
- [ ] Segundo DC (HA) documentado para el futuro (`docs/`)