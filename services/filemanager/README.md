# 📁 `filemanager` — gestor web de archivos (Filebrowser)

Interfaz web sobre los **shares SMB del DC** (`/srv/samba/departamentos` y
`/srv/samba/respaldo`). No copia ni mueve datos: monta esos directorios en
el contenedor y los sirve en `https://archivos.sudoers.lan`.

> **Proyecto archivado:** Filebrowser fue archivado el 2026-09-01 (sin
> releases ni fixes de seguridad). Por eso la imagen está **pinneada** en
> `FILEBROWSER_TAG=v2.63.23` (nada de `:latest`). Ver
> <https://github.com/filebrowser/filebrowser/security/advisories>.

## Composición

| Contenedor | Imagen | Puerto | Rol |
| --- | --- | --- | --- |
| `tso-files` | `filebrowser/filebrowser:v2.63.23` | sin publicar (solo nginx) | app en `:80` sobre `/srv` del contenedor |

- `entrypoint.sh` (montado en el contenedor) prepara todo antes de arrancar:
  crea la BD + admin en el **primer** arranque, sincroniza los usuarios de
  `.env` y fija los modos `0664` (archivos) / `0775` (carpetas).
- Volumenes: `files_config` (`/config/settings.json`) y `files_db`
  (`/database/filebrowser.db`).
- Bind mounts (read-write): `${FILES_SHARES_DIR:-/srv/samba}/departamentos`
  → `/srv/departamentos` y `…/respaldo` → `/srv/respaldo`.
  **Los homes personales (`[homes]`) NO se publican** (cada usuario accede
  al suyo por SMB/`\\dc1\usuario`).

## Variables (`.env`)

| Var | Default | Qué hace |
| --- | --- | --- |
| `FILEBROWSER_TAG` | `v2.63.23` | tag de la imagen (no usar `latest`) |
| `FILES_ADMIN_USER` / `FILES_ADMIN_PASS` | `admin` / **obligatoria** | usuario administrador (clave siempre sincronizada desde `.env`) |
| `FILES_USERS` | vacío | usuarios equipo, mismo formato que `MAIL_USERS` (`"user:pass user2:pass2"`) |
| `FILES_SHARES_DIR` | `/srv/samba` | base de los shares (para probar fuera del server) |
| `FILES_GID` | `0` | gid primario del contenedor → grupo de los archivos creados |
| `FILES_FILE_MODE` / `FILES_DIR_MODE` | `0664` / `0775` | permisos de lo creado desde la web |
| `FILES_UMASK` | `002` | umask del proceso (con `022` saldrían `0644`/`0755`) |
| `FILES_MIN_PASS_LEN` | `10` | mínimo de longitud de clave (el default de Filebrowser es 12) |

### `FILES_GID` — importante para la escritura mixta (web + SMB)

```bash
stat -c %g /srv/samba/departamentos     # en el server
# o: getent group srv-files
```

Con `FILES_GID=<gid>` los archivos nuevos quedan `root:<grupo-del-share>`
con modo `0664`, de modo que los miembros del grupo AD siguen pudiendo
**escribirlos desde SMB** (y viceversa: lo que se crea desde SMB es visible
y editable en la web). Si el directorio tiene setgid/ACL por defecto, el
grupo se hereda igual.

## Uso

1. `.env`: definir `FILES_ADMIN_PASS` y, si se quiere, `FILES_USERS`.
2. `docker compose up -d filemanager` (y `docker compose up -d web` si es la
   primera vez, para recargar el server block).
3. Registrar el DNS: `sudo bash dc/dns-records.sh`.
4. Entrar a `https://archivos.sudoers.lan` con el admin (o un usuario de
   `FILES_USERS`). Desde el menú de usuario → *Settings* se crean/bloquean
   usuarios, y en la web se gestionan permisos por usuario.

## Verificación

```bash
# contenedor + proceso
docker compose ps filemanager && docker logs tso-files --tail 20

# login (debe dar 200 y un token)
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  https://archivos.sudoers.lan/api/login \
  -H 'Content-Type: application/json' \
  -d '{"username":"admin","password":"<pass>"}'

# DNS + TLS
dig +short archivos.sudoers.lan     # 192.168.0.2
```

## Problemas típicos

- **413 Request Entity Too Large** → no se recargó nginx (el server block
  trae `client_max_body_size 0`): `docker compose restart web`.
- **`Falta FILES_ADMIN_PASS`** → falta la clave en `.env`.
- **`user: '0:<gid>'` / permisos raros en el share** → revisar `FILES_GID`
  y los modos: `ls -la /srv/samba/departamentos`.
- **404 en la URL** → DNS: `sudo bash dc/dns-records.sh` (agrega `archivos`).
