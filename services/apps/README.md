# Servicio: Apps internas — PENDIENTE

Carpeta reservada para **aplicaciones internas** de la organización (apps).
Cada app puede vivir en su propio subdirectorio o contenedor del compose.

## Ideas (Fase 5)

- Wiki / documentación (DokuWiki, Bookstack, outline…).
- Gestor de tareas / helpdesk.
- Vault (gestor de contraseñas) si hace falta.
- NFS/share aislado adicional si se necesita (el SMB lo da el DC).

## Criterios

- Se publican por el proxy (`apps.sudoers.lan` o subdominio propio) solo si
  son web.
- La auth preferida es contra el AD (usuarios/grupos `srv-*`); se evalúa por
  app (algunas tienen auth LDAP nativa).
- Backend de datos en `services/database`.

## Pendiente de desarrollo

- [ ] Elegir apps concretas
- [ ] Dockerfile/compose por app
- [ ] README por app

## Referencias

- Arquitectura: [`docs/arquitectura.md`](../../docs/arquitectura.md) — §9/§10