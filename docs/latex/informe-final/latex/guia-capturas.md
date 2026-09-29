# Guía de Capturas de Pantalla — Informe Final

Ejecuta los comandos en **la máquina donde está instalado el servidor** (Debian/Rocky Linux).

---

## 1. Preparación del entorno

**Archivo:** `captura-ip-fija.png`
**Comando:**
```bash
ip addr show
hostnamectl status
```
**Qué mostrar:** la configuración de IP fija y el hostname del servidor.

---

## 2. Instalación de paquetes

**Archivo:** `captura-instalacion.png`
**Comando:**
```bash
apt update && apt install -y isc-dhcp-server bind9 apache2
```
**Qué mostrar:** la salida de la instalación de los paquetes.

---

## 3. Configuración del servidor DHCP

**Archivo:** `captura-dhcp-conf.png`
**Comando:**
```bash
cat /etc/dhcp/dhcpd.conf
systemctl status isc-dhcp-server
```
**Qué mostrar:** el archivo de configuración y el estado del servicio.

---

## 4. Configuración del servidor DNS (BIND9)

**Archivo:** `captura-bind9-conf.png`
**Comando:**
```bash
cat /etc/bind/named.conf.local
named-checkconf
```
**Qué mostrar:** la configuración de zonas y la verificación de sintaxis.

---

## 5. Configuración del servidor Web

**Archivo:** `captura-web-conf.png`
**Comando:**
```bash
cat /etc/apache2/sites-available/000-default.conf
systemctl status apache2
```
**Qué mostrar:** la configuración del sitio web y el estado del servicio.

---

## 6. Pruebas funcionales

**Archivo:** `captura-pruebas.png`
**Comando:**
```bash
dig @localhost example.com
ping -c 4 <ip-servidor>
curl -I http://localhost
```
**Qué mostrar:** las pruebas de resolución DNS, conectividad y acceso web.

---

## Consejos generales

- Usa **ctrl+shift+s** (GNOME) o **scrot** / **flameshot** para tomar capturas de área selectiva.
- Si el terminal tiene mucho texto, muestra solo la parte relevante.
- Todas las capturas se guardan en `figuras/` y el PDF las muestra automáticamente al compilar.
