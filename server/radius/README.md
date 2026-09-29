# server/radius/ — FreeRADIUS (WiFi WPA2-Enterprise / 802.1X)

Servidor **RADIUS nativo** en dc1: valida el usuario y contraseña del
**AD** para la red WiFi `sudoers`. El router TP-Link hace de
authenticator y reenvía a `192.168.0.2:1812`.

```text
cliente (PEAP/MSCHAPv2) → router 192.168.0.1 → FreeRADIUS (dc1:1812)
                                                └→ ntlm_auth → winbind → AD (Samba)
```

## Instalación (en dc1)

```bash
git pull
echo "RADIUS_SECRET=$(openssl rand -hex 16)" >> .env   # si no existe
sudo bash server/deploy.sh
```

El deploy: instala `freeradius`/`freeradius-utils`, habilita
`ntlm auth = mschapv2-and-ntlmv2-only` en smb.conf (reinicia el DC si
faltaba), copia `clients.conf` + `mod-mschap` con los valores de `.env`,
genera la CA/EAP si no existe, valida con `freeradius -XC`, arranca el
servicio y cronifica la sonda cada 5 min.

## Config del router (UI, manual)

Wireless → Security → **WPA/WPA2-Enterprise**:

| Campo | Valor |
| --- | --- |
| Radius Server IP | `192.168.0.2` |
| Radius Server Port | `1812` |
| Radius Server Password | `RADIUS_SECRET` de `.env` (**igual**, sin comillas) |

## Verificación (en dc1)

```bash
# 1) servicio escuchando
sudo ss -ulnp | grep 1812

# 2) autenticación real contra el AD (MSCHAPv2, no necesita WiFi)
sudo radtest -t mschap2 joaquin '<clave AD>' 127.0.0.1:1812 testing123
#    → Access-Accept = OK; Access-Reject con clave mala = también OK
#      (el server respondió); "No reply" = winbind/ntlm_auth roto.

# 3) diagnóstico fino si falla
sudo freeradius -X     # debug en vivo (Ctrl+C para salir)
journalctl -u freeradius -n 50
```

## Conexión de clientes

Ver [`clients/wifi.md`](../../clients/wifi.md) (Windows y Linux, con la
CA del RADIUS en `/etc/freeradius/3.0/certs/ca.pem` y `ca.der`).

## Monitoreo

`radius-check.sh` escribe `tso_radius_up` en
`/var/lib/tso-backup/radius.prom` (cada 5 min, `/etc/cron.d/tso-radius`).
Alertas: `RadiusNoResponde` / `RadiusNuncaVerificado`
(`services/monitoring/prometheus/rules/servicios.yml`).

## Troubleshooting

| Síntoma | Causa probable |
| --- | --- |
| `No reply from server` en radtest | winbindd/`ntlm_auth` caído o `freerad` sin grupo `winbindd_priv` |
| `NT_STATUS_LOGON_FAILURE` | clave de AD incorrecta (o username en formato distinto) |
| Cliente no valida el cert EAP | falta importar `ca.der`/`ca.pem` en el cliente |
| Router sin respuesta del server | revisar `RADIUS_SECRET` (UI del router vs `.env`) y `nft` (`udp 1812 desde 192.168.0.1`) |
| Cambio de contraseña falla en WiFi | no está configurado `passchange` (hacerlo en el DC con AD) |

**Plan B** (si `ntlm_auth` no anda sobre el DC): usar el modo directo
`winbind_username`/`winbind_domain` del módulo mschap, o bien
`rlm_ldap` + LDAPS (`unicodePwd`) con inner PAP/TTLS.
