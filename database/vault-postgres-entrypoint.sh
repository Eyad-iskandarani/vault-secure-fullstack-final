#!/usr/bin/env bash

set -Eeuo pipefail

VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
VAULT_SECRET_PATH="${VAULT_SECRET_PATH:-kv/data/secure-fullstack}"
VAULT_TOKEN_FILE="${VAULT_TOKEN_FILE:-/run/secrets/vault_token}"

if [[ ! -r "${VAULT_TOKEN_FILE}" ]]; then
    echo "Error: Vault token file is not readable."
    exit 1
fi

VAULT_TOKEN="$(tr -d '\r\n' < "${VAULT_TOKEN_FILE}")"

if [[ -z "${VAULT_TOKEN}" ]]; then
    echo "Error: Vault token file is empty."
    exit 1
fi

VAULT_RESPONSE=""

for ATTEMPT in $(seq 1 30); do
    if VAULT_RESPONSE="$(
        curl \
            --silent \
            --show-error \
            --fail \
            --header "X-Vault-Token: ${VAULT_TOKEN}" \
            "${VAULT_ADDR}/v1/${VAULT_SECRET_PATH}"
    )"; then
        break
    fi

    echo "Vault attempt ${ATTEMPT}/30 failed. Retrying..."
    sleep 2
done

if [[ -z "${VAULT_RESPONSE}" ]]; then
    echo "Error: Unable to retrieve PostgreSQL credentials from Vault."
    exit 1
fi

POSTGRES_DB="$(
    printf '%s' "${VAULT_RESPONSE}" |
        jq -er '.data.data.DB_NAME'
)"

POSTGRES_USER="$(
    printf '%s' "${VAULT_RESPONSE}" |
        jq -er '.data.data.DB_USER'
)"

POSTGRES_PASSWORD="$(
    printf '%s' "${VAULT_RESPONSE}" |
        jq -er '.data.data.DB_PASSWORD'
)"

if [[ -z "${POSTGRES_DB}" ||
      -z "${POSTGRES_USER}" ||
      -z "${POSTGRES_PASSWORD}" ]]; then
    echo "Error: Vault returned incomplete PostgreSQL credentials."
    exit 1
fi

export POSTGRES_DB
export POSTGRES_USER
export POSTGRES_PASSWORD

unset VAULT_TOKEN
unset VAULT_RESPONSE

echo "PostgreSQL credentials retrieved dynamically from Vault."

exec /usr/local/bin/docker-entrypoint.sh "$@"
