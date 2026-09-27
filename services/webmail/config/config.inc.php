<?php
// ===================================================================
// services/webmail/config/config.inc.php — configuración extra de Roundcube.
//
// El archivo lo incluye el propio contenedor (la imagen escribe
// config.docker.inc.php y agrega un include por cada *.php de
// /var/roundcube/config), así que acá SOLO se pisa lo que hace falta.
// Los valores de conexión (IMAP/SMTP, db, skin) vienen del compose.
// ===================================================================

// El proxy (nginx) termina TLS y reenvía X-Forwarded-Proto: https.
// Sin esta whitelist Roundcube ignora ese header, cree que la petición
// es HTTP y no marca la cookie de sesión como Secure.
$config['proxy_whitelist'] = ['127.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'];

// Solo este nombre puede usarse como Host (evita Host header spoofing).
$config['trusted_host'] = ['webmail.sudoers.lan'];

// El certificado autofirmado de tso-mail no está en la CA del sistema:
// se valida el TLS pero no la identidad del peer (red interna aislada).
$config['smtp_conn_options'] = [
    'ssl' => [
        'verify_peer' => false,
        'verify_peer_name' => false,
    ],
];
$config['imap_conn_options'] = [
    'ssl' => [
        'verify_peer' => false,
        'verify_peer_name' => false,
    ],
];

// Logs a stdout → `docker compose logs webmail`.
$config['log_driver'] = 'stdout';
