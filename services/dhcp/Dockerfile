# Servidor DHCP con Kea
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends kea-dhcp4-server && \
    rm -rf /var/lib/apt/lists/*

COPY kea-dhcp4.conf /etc/kea/kea-dhcp4.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 67/udp

CMD ["/entrypoint.sh"]