# Servidor de impresión CUPS con impresora virtual PDF (cups-pdf)
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        cups \
        cups-client \
        cups-pdf \
        printer-driver-all \
        whois && \
    rm -rf /var/lib/apt/lists/*

COPY cupsd.conf /etc/cups/cupsd.conf
COPY entrypoint.sh /entrypoint.sh
RUN sed -i 's/\r$//' /entrypoint.sh && chmod +x /entrypoint.sh

# Puerto de la interfaz web de CUPS
EXPOSE 631

# Directorio donde cups-pdf guarda los PDFs generados
VOLUME ["/var/spool/cups-pdf/OUT"]

CMD ["/entrypoint.sh"]