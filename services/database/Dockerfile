# Servidor de base de datos con PostgreSQL 15 (Debian bookworm)
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive
ENV PG_VERSION=15

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        postgresql \
        postgresql-client && \
    rm -rf /var/lib/apt/lists/*

# Copiar entrypoint (inicializa cluster, aplica .env y arranca)
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

EXPOSE 5432

CMD ["/entrypoint.sh"]