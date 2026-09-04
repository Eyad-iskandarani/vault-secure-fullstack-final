FROM postgres:16-bookworm

RUN apt-get update && \
    apt-get install --yes --no-install-recommends \
        ca-certificates \
        curl \
        jq && \
    rm -rf /var/lib/apt/lists/*

COPY vault-postgres-entrypoint.sh \
    /usr/local/bin/vault-postgres-entrypoint.sh

RUN chmod 755 \
    /usr/local/bin/vault-postgres-entrypoint.sh

ENTRYPOINT ["/usr/local/bin/vault-postgres-entrypoint.sh"]

CMD ["postgres"]
