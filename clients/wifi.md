# clients/wifi.md — Conectarse al WiFi `sudoers` (WPA2-Enterprise)

La red `sudoers` usa **802.1X (WPA2-Enterprise) con PEAP/MSCHAPv2**: el
usuario y la contraseña son los del **dominio AD**. El servidor RADIUS
es dc1 (`192.168.0.2:1812`, `server/radius/`).

## 0) Conseguir la CA del servidor (una vez)

La CA firma el certificado con el que el cliente valida al servidor EAP.

```bash
scp joaquin@192.168.0.2:/etc/freeradius/3.0/certs/ca.der ./radius-ca.der
# (en Windows también sirve ca.pem, renombrado a .cer)
```

## 1) Windows (contabilidad/marketing)

1. Importar la CA: doble clic sobre `radius-ca.der` → **Instalar
   certificado** → **Local equipo** → **Autoridades de certificación
   raíz de confianza**.
2. `ncpla.cpl` (Ejecutar) → clic derecho en el adaptador →
   **Propiedades** → pestaña **Autenticación**:
   - ☑ Habilitar autenticación IEEE 802.1X
   - Método: **EAP-PEAP**
   - Configuración: método de autenticación **EAP-MSCHAPv2**
   - ☑ Validar certificado del servidor (CN `radius.sudoers.lan`)
3. Conectarse a `sudoers` → credenciales: `SUDOERS\usuario` (o
   `usuario@sudoers.lan`) y la clave del dominio.

> Si el certificado no valida en algún equipo, revisá que la CA quedó en
> "Autoridades raíz de confianza" del **equipo** (no del usuario).

## 2) Linux (NetworkManager / nmcli)

```bash
# CA copiada en /etc/ssl/certs/radius-ca.der (o ruta cualquiera)
sudo cp radius-ca.der /usr/local/share/ca-certificates/radius-sudoers.crt
sudo update-ca-certificates          # Debian/Ubuntu

sudo nmcli connection add type wifi con-name sudoers ssid sudoers \
    wifi-sec.key-mgmt wpa-eap \
    802-1x.eap peap \
    802-1x.identity 'joaquin' \
    802-1x.phase2-auth mschapv2 \
    802-1x.password '<clave AD>' \
    802-1x.password-flags 0 \
    802-1x.ca-cert /usr/local/share/ca-certificates/radius-sudoers.crt \
    802-1x.domain-suffix-match sudoers.lan

sudo nmcli connection up sudoers
```

El identity puede ser `joaquin`, `SUDOERS\joaquin` o `joaquin@sudoers.lan`
(la capa interna MSCHAPv2 usa el usuario simple).

## 3) Linux sin NetworkManager (`wpa_supplicant`)

```
# /etc/wpa_supplicant/wpa_supplicant.conf
network={
    ssid="sudoers"
    key_mgmt=WPA-EAP
    eap=PEAP
    identity="joaquin@sudoers.lan"
    password="clave-del-dominio"
    phase2="auth=MSCHAPV2"
    ca_cert="/etc/ssl/certs/radius-sudoers.pem"
    domain_suffix_match="sudoers.lan"
}
```

## Verificación previa (sin WiFi)

En dc1, con cualquier usuario del dominio:

```bash
sudo radtest -t mschap joaquin '<clave>' 127.0.0.1:1812 0 testing123
# Access-Accept → todo el camino (FreeRADIUS + ntlm_auth + AD) funciona
```
