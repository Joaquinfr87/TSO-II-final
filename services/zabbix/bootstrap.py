#!/usr/bin/env python3
"""Configura Zabbix (server en 192.168.0.3) por API: media types, usuarios,
grupos, hosts, templates y actions de alerta.

Uso (desde cualquier máquina de la LAN, no requiere SSH):

    cd services/zabbix
    cp .env.example .env      # completar
    python3 bootstrap.py      # idempotente: se puede correr de nuevo

Verificación posterior:

    python3 bootstrap.py --status
"""

import json
import os
import pathlib
import sys
import urllib.request

HERE = pathlib.Path(__file__).resolve().parent
API = None
TOKEN = None


# ------------------------------------------------------------------ helpers
def load_env(path):
    """Lee KEY=VALUE de un .env (sin dependencias)."""
    out = {}
    if not path.exists():
        return out
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        out[k.strip()] = v.split("#")[0].strip().strip('"').strip("'")
    return out


def cfg():
    file_env = load_env(HERE / ".env")
    root_env = load_env(HERE.parent.parent / ".env")

    def get(key, default=""):
        return os.environ.get(key) or file_env.get(key) or root_env.get(key) or default

    users = get("ZBX_ALL_USERS") or " ".join(
        u.split(":")[0] for u in get("MAIL_USERS").split()
    )
    return {
        "url": get("ZBX_URL", "http://192.168.0.3/api_jsonrpc.php"),
        "user": get("ZBX_USER", "Admin"),
        "password": get("ZBX_PASSWORD", "zabbix"),
        "smtp_server": get("SMTP_SERVER", "192.168.0.2"),
        "smtp_port": get("SMTP_PORT", "25"),
        "smtp_helo": get("SMTP_HELO", "mail.sudoers.lan"),
        "smtp_from": get("SMTP_FROM", "zabbix@mail.sudoers.lan"),
        "mail_domain": get("MAIL_DOMAIN", "mail.sudoers.lan"),
        "admins": (get("ZBX_ADMINS") or "joaquin david nicolas").split(),
        "all_users": users.split(),
        "user_password": get("ZBX_USER_PASSWORD", "Correo2026"),
        "dc1_ip": get("DC1_IP", "192.168.0.2"),
        "zabbix_ip": get("ZABBIX_IP", "192.168.0.3"),
    }


def rpc(method, params=None, token=None):
    body = {"jsonrpc": "2.0", "method": method, "params": params or {}, "id": 1}
    req = urllib.request.Request(
        API,
        data=json.dumps(body).encode(),
        headers={
            "Content-Type": "application/json-rpc",
            **({"Authorization": "Bearer " + token} if token else {}),
        },
    )
    with urllib.request.urlopen(req, timeout=60) as r:
        res = json.loads(r.read())
    if "error" in res:
        raise RuntimeError(
            "%s -> %s %s" % (method, res["error"].get("message"), res["error"].get("data"))
        )
    return res.get("result")


def login(user, password):
    return rpc("user.login", {"username": user, "password": password})


def say(msg):
    print("==> " + msg, flush=True)


# ------------------------------------------------------------------- pasos
def setup_media_type(c):
    say("Media type Email -> SMTP %s:%s (%s)" % (c["smtp_server"], c["smtp_port"], c["smtp_from"]))
    rpc(
        "mediatype.update",
        {
            "mediatypeid": "1",
            "smtp_server": c["smtp_server"],
            "smtp_port": c["smtp_port"],
            "smtp_helo": c["smtp_helo"],
            "smtp_email": c["smtp_from"],
            "smtp_security": "0",
            "smtp_authentication": "0",
            "status": "0",
        },
        TOKEN,
    )


def ensure_hostgroup(name):
    res = rpc("hostgroup.get", {"filter": {"name": [name]}}, TOKEN)
    if res:
        return res[0]["groupid"]
    return rpc("hostgroup.create", {"name": name}, TOKEN)["groupids"][0]


def ensure_usergroup(name, groupid):
    res = rpc("usergroup.get", {"filter": {"name": [name]}}, TOKEN)
    if res:
        rpc(
            "usergroup.update",
            {
                "usrgrpid": res[0]["usrgrpid"],
                "rights": [{"id": groupid, "permission": 2}],
                "users_status": 0,
            },
            TOKEN,
        )
        return res[0]["usrgrpid"]
    return rpc(
        "usergroup.create",
        {
            "name": name,
            "users_status": 0,
            "gui_access": 0,
            "rights": [{"id": groupid, "permission": 2}],
        },
        TOKEN,
    )["usrgrpids"][0]


def import_templates():
    for f in sorted((HERE / "templates").glob("*.yaml")):
        say("Importando template %s" % f.name)
        rpc(
            "configuration.import",
            {
                "format": "yaml",
                "source": f.read_text(),
                "rules": {
                    "template_groups": {"createMissing": True, "updateExisting": True},
                    "templates": {"createMissing": True, "updateExisting": True},
                    "items": {"createMissing": True, "updateExisting": True},
                    "triggers": {"createMissing": True, "updateExisting": True},
                    "discoveryRules": {"createMissing": True, "updateExisting": True},
                    "valueMaps": {"createMissing": True, "updateExisting": True},
                },
            },
            TOKEN,
        )


def template_id(name):
    res = rpc("template.get", {"filter": {"host": [name]}, "output": ["templateid"]}, TOKEN)
    if not res:
        raise RuntimeError("template no encontrado: " + name)
    return res[0]["templateid"]


def setup_host(params):
    res = rpc("host.get", {"filter": {"host": [params["host"]]}, "output": ["hostid"]}, TOKEN)
    if res:
        hostid = res[0]["hostid"]
        upd = {"hostid": hostid}
        if params.get("name"):
            upd["name"] = params["name"]
        if params.get("groups"):
            upd["groups"] = [{"groupid": g} for g in params["groups"]]
        if params.get("templates"):
            upd["templates"] = [{"templateid": template_id(t)} for t in params["templates"]]
        if params.get("ip"):
            ifs = rpc(
                "host.get",
                {"hostids": hostid, "selectInterfaces": ["interfaceid"]},
                TOKEN,
            )[0]["interfaces"]
            iface = ifs[0]
            upd["interfaces"] = [
                {
                    "interfaceid": iface["interfaceid"],
                    "type": 1,
                    "main": 1,
                    "useip": 1,
                    "ip": params["ip"],
                    "dns": "",
                    "port": params.get("port", "10050"),
                }
            ]
        rpc("host.update", upd, TOKEN)
        say("Host actualizado: %s (%s)" % (params["host"], params.get("ip", "")))
        return hostid

    hostid = rpc(
        "host.create",
        {
            "host": params["host"],
            "name": params.get("name", params["host"]),
            "groups": [{"groupid": g} for g in params["groups"]],
            "templates": [{"templateid": template_id(t)} for t in params["templates"]],
            "interfaces": [
                {
                    "type": 1,
                    "main": 1,
                    "useip": 1,
                    "ip": params["ip"],
                    "dns": "",
                    "port": params.get("port", "10050"),
                }
            ],
        },
        TOKEN,
    )["hostids"][0]
    say("Host creado: %s (%s)" % (params["host"], params["ip"]))
    return hostid


def ensure_user(username, fullname, email, groups):
    medias = [
        {
            "mediatypeid": "1",
            "sendto": [email],
            "active": "0",
            "severity": "63",
            "period": "1-7,00:00-24:00",
        }
    ]
    res = rpc("user.get", {"filter": {"username": [username]}, "output": ["userid"]}, TOKEN)
    if res:
        rpc(
            "user.update",
            {"userid": res[0]["userid"], "medias": medias, "usrgrps": [{"usrgrpid": g} for g in groups]},
            TOKEN,
        )
        return
    rpc(
        "user.create",
        {
            "username": username,
            "passwd": c_user_password,
            "name": fullname,
            "usrgrps": [{"usrgrpid": g} for g in groups],
            "medias": medias,
        },
        TOKEN,
    )


def setup_actions(admins_grpid, users_grpid):
    defs = [
        {
            "name": "TSO - Servicio o contenedor caído (admins)",
            "eventsource": 0,
            "status": 0,
            "esc_period": "1h",
            "filter": {
                "evaltype": 1,
                "conditions": [
                    {"conditiontype": 26, "operator": 0, "value": "notify", "value2": "admins"},
                ],
            },
            "operations": [
                {
                    "operationtype": 0,
                    "opmessage": {"default_msg": 1},
                    "opmessage_grp": [{"usrgrpid": admins_grpid}],
                }
            ],
        },
        {
            "name": "TSO - Servicio de Zabbix (re)iniciado (todos los usuarios)",
            "eventsource": 0,
            "status": 0,
            "esc_period": "1h",
            "filter": {
                "evaltype": 1,
                "conditions": [
                    {"conditiontype": 26, "operator": 0, "value": "notify", "value2": "zabbix-arrancada"},
                ],
            },
            "operations": [
                {
                    "operationtype": 0,
                    "opmessage": {
                        "default_msg": 0,
                        "subject": "El servicio de Zabbix se (re)inició",
                        "message": (
                            "El servicio de monitoreo Zabbix volvio a estar arriba.\r\n"
                            "Host: {HOST.NAME}\r\n"
                            "Evento: {EVENT.NAME}\r\n"
                            "Fecha: {EVENT.DATE} {EVENT.TIME}\r\n"
                            "Detalle: {TRIGGER.URL}\r\n"
                        ),
                    },
                    "opmessage_grp": [{"usrgrpid": users_grpid}],
                },
                {
                    "operationtype": 0,
                    "opmessage": {"default_msg": 1},
                    "opmessage_grp": [{"usrgrpid": admins_grpid}],
                },
            ],
        },
    ]
    for d in defs:
        have = rpc("action.get", {"filter": {"name": [d["name"]]}}, TOKEN)
        if have:
            rpc("action.update", dict(d, actionid=have[0]["actionid"]), TOKEN)
            say("Action actualizada: %s" % d["name"])
        else:
            rpc("action.create", d, TOKEN)
            say("Action creada: %s" % d["name"])


# ------------------------------------------------------------------- main
def main():
    global API, TOKEN, c_user_password
    c = cfg()
    API = c["url"]
    c_user_password = c["user_password"]

    if "--status" in sys.argv:
        TOKEN = login(c["user"], c["password"])
        return status()

    say("Login %s" % API)
    TOKEN = login(c["user"], c["password"])

    setup_media_type(c)

    import_templates()

    g_servers = ensure_hostgroup("servidores")
    g_usuarios = ensure_usergroup("usuarios", g_servers)
    g_admins = ensure_usergroup("admins", g_servers)

    setup_host(
        {
            "host": "dc1",
            "name": "dc1 (servidor principal)",
            "ip": c["dc1_ip"],
            "groups": [g_servers],
            "templates": [
                "Linux by Zabbix agent",
                "ICMP Ping",
                "TSO - Docker agent2",
                "TSO - Servicios TCP sin agente",
            ],
        }
    )
    setup_host(
        {
            "host": "Zabbix server",
            "ip": c["zabbix_ip"],
            "groups": ["4", g_servers],
            "templates": [
                "Zabbix server health",
                "Linux by Zabbix agent",
                "ICMP Ping",
                "TSO - Servicio Zabbix",
            ],
        }
    )

    say("Usuarios (%d) -> %s" % (len(set(c["all_users"])), c["mail_domain"]))
    seen = []
    for u in c["all_users"]:
        if u in seen:
            continue
        seen.append(u)
        groups = [g_usuarios] + ([g_admins] if u in c["admins"] else [])
        ensure_user(u, u, "%s@%s" % (u, c["mail_domain"]), groups)

    setup_actions(g_admins, g_usuarios)
    print("\nListo. Estado actual:")
    return status()


def status():
    hosts = rpc(
        "host.get",
        {
            "output": ["host", "name"],
            "selectInterfaces": ["ip"],
            "selectParentTemplates": ["host"],
        },
        TOKEN,
    )
    for h in hosts:
        tpl = ", ".join(t["host"] for t in h.get("parentTemplates", []))
        print(
            "  host=%-16s ip=%-15s\n      templates: %s"
            % (h["host"], h["interfaces"][0]["ip"] if h["interfaces"] else "-", tpl or "-")
        )
    items = rpc(
        "item.get",
        {"output": ["name", "state", "error", "lastvalue", "key", "delay"],
         "filter": {"key": ["net.tcp.service[tcp,,80]", "net.tcp.service[tcp,,10051]",
                            "net.tcp.service[tcp,,25]", "docker.containers.running"]},
         "selectHosts": ["host"]},
        TOKEN,
    )
    print("  items de muestra (state 0=ok, 1=sin soporte):")
    for i in items:
        print(
            "    %-14s %-34s state=%s val=%-6s %s"
            % (i["hosts"][0]["host"], i["name"], i["state"], i["lastvalue"],
               i["error"][:70])
        )
    print("  problemas abiertos:")
    ev = rpc("event.get", {"output": ["eventid", "name", "severity", "clock"],
                           "source": 0, "object": 0, "recent": True,
                           "select_tags": "extend", "sortfield": "-clock",
                           "limit": 10}, TOKEN)
    for e in ev:
        tags = ",".join("%s=%s" % (t["tag"], t["value"]) for t in e.get("tags", []))
        print("    sev=%s %s [%s]" % (e["severity"], e["name"], tags))
    print("  actions:")
    for a in rpc("action.get", {"output": ["name", "status"],
                                "filter": {"name": ["TSO - Servicio o contenedor caído (admins)",
                                                    "TSO - Servicio de Zabbix (re)iniciado (todos los usuarios)"]}},
                 TOKEN):
        print("    %s (status=%s)" % (a["name"], a["status"]))
    print("  ultimas alertas (0=en cola,1=enviada,2=fallida):")
    al = rpc("alert.get", {"output": ["alertid", "clock", "status", "error", "sendto",
                                       "subject"], "sortfield": "-clock", "limit": 15}, TOKEN)
    for a in al:
        print("    %s -> %s status=%s %s" % (
            __import__("datetime").datetime.fromtimestamp(int(a["clock"])).strftime("%H:%M:%S"),
            a["sendto"], a["status"], (a.get("error") or "")[:60]))
        print("        %s" % a["subject"][:100])
    return 0


if __name__ == "__main__":
    sys.exit(main())
