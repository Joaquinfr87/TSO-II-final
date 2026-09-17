# Servidor de correo con Postfix (SMTP) y Dovecot (IMAP/POP3)
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        postfix \
        dovecot-imapd \
        dovecot-pop3d \
        libsasl2-modules \
        openssl && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /etc/dovecot/conf.d

COPY main.cf /etc/postfix/main.cf
COPY 10-mail.conf /etc/dovecot/conf.d/10-mail.conf
COPY 10-auth.conf /etc/dovecot/conf.d/10-auth.conf
COPY 10-master.conf /etc/dovecot/conf.d/10-master.conf
COPY 10-ssl.conf /etc/dovecot/conf.d/10-ssl.conf
COPY 10-logging.conf /etc/dovecot/conf.d/10-logging.conf

EXPOSE 25 110 143 587 993 995

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

CMD ["/entrypoint.sh"]