# Servicio: DNS (Bind9) — RETIRADO

En esta arquitectura **el DNS del dominio lo maneja el DC de Samba**
(`dc/provision.sh`, backend `SAMBA_INTERNAL`). Bind9 ya no compite con la
zona `sudoers.lan`.

## Por qué

En un Active Directory el controlador de dominio **debe** ser autoritativo de
la zona del dominio (registros `_sites`, `_tcp`, `_kerberos`, `_ldap`, SRV,
etc.). Si Bind9 fuera el autoritativo, el DC tendría que actualizarlo vía
`samba_dnsupdate` (complejo y frágil). El DC nativo con DNS interno resuelve
eso de forma nativa.

## Qué pasó con el servicio del lab

| Archivo del lab (`TSO-II/services/dns/`) | Destino acá |
| --- | --- |
| Bind9 contenedor (`53:53`) | **eliminado** del compose (el 53 es del DC nativo) |
| Zonas con Views (wlo1/eno1) | **sin efecto**: una sola red `192.168.0.x` |

## Si más adelante se quiere un caché/reenvío

Se puede agregar un `dnsmasq` o un Bind9 como **forwarder/caché** del DC
(no autoritativo de la zona). Se documenta en `docs/` cuando aplique.

## Verificación del DNS provisto por el DC

```bash
dig @192.168.0.10 sudoers.lan
dig @192.168.0.10 _kerberos._udp.sudoers.lan SRV
```

## Referencias

- DC nativo: [`../../dc/README.md`](../../dc/README.md)
- Regla 2 de `AGENTS.md` (DNS lo manda el DC)