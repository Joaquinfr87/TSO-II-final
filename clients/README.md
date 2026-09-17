# clients/ — Guías para unir clientes al dominio — PENDIENTE

Carpeta reservada para las guías de unión de equipos al AD.

## Plan

| Archivo | Contenido (Fase 2) |
| --- | --- |
| `linux.md` | `realm join` + SSSD: auth Kerberos/LDAP, sudo por grupos AD, homes con `pam_mkhomedir`, NTP contra el DC |
| `windows.md` | Unir Windows (contabilidad/marketing) al dominio `SUDOERS` (auth + SMB + Kerberos); alcance de GPO |

## Pendiente de desarrollo

- [ ] `linux.md` — pasos y verificación
- [ ] `windows.md` — pasos y verificación

## Referencias

- Identidad: [`docs/arquitectura.md`](../docs/arquitectura.md) — §6
- DC: [`../dc/README.md`](../dc/README.md)