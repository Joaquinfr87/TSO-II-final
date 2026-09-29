# clients/ — Guías para clientes (WiFi + unión al dominio)

## Plan

| Archivo | Contenido | Estado |
| --- | --- | --- |
| `wifi.md` | WiFi `sudoers` con WPA2-Enterprise (PEAP/MSCHAPv2 + usuario AD) | ✅ |
| `linux.md` | `realm join` + SSSD: auth Kerberos/LDAP, sudo por grupos AD, homes con `pam_mkhomedir`, NTP contra el DC | pendiente (Fase 2) |
| `windows.md` | Unir Windows (contabilidad/marketing) al dominio `SUDOERS` (auth + SMB + Kerberos); alcance de GPO | pendiente (Fase 2) |

## Pendiente de desarrollo

- [ ] `linux.md` — pasos y verificación
- [ ] `windows.md` — pasos y verificación

## Referencias

- Identidad: [`docs/arquitectura.md`](../docs/arquitectura.md) — §6
- DC: [`../dc/README.md`](../dc/README.md)