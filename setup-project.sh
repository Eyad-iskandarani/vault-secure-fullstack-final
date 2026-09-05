#!/usr/bin/env bash

set -Eeuo pipefail

PROJECT_DIRECTORY="$(
    cd "$(dirname "${BASH_SOURCE[0]}")" &&
    pwd
)"

VAULT_COMPOSE="${PROJECT_DIRECTORY}/vault/docker-compose.yaml"
VAULT_INITIALIZATION="${PROJECT_DIRECTORY}/.local/vault-init.json"
VAULT_TOKEN_FILE="${PROJECT_DIRECTORY}/vault/token"
VAULT_ADDRESS="http://127.0.0.1:8200"

cd "${PROJECT_DIRECTORY}"

echo "=========================================="
echo "Secure Full-Stack Project Setup"
echo "=========================================="

# --------------------------------------------------
# Check required programs
# --------------------------------------------------

for COMMAND in docker curl jq openssl; do
    if ! command -v "${COMMAND}" >/dev/null 2>&1; then
        echo "Error: ${COMMAND} is not installed."
        exit 1
    fi
done

if ! docker compose version >/dev/null 2>&1; then
    echo "Error: Docker Compose is not available."
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "Error: Docker is not running or your user cannot access it."
    exit 1
fi

# --------------------------------------------------
# Prepare local runtime directories
# --------------------------------------------------

mkdir -p "${PROJECT_DIRECTORY}/.local"
mkdir -p "${PROJECT_DIRECTORY}/vault/data"

chmod 700 "${PROJECT_DIRECTORY}/.local"

echo "Preparing Vault data directory..."

sudo chown -R 100:100 "${PROJECT_DIRECTORY}/vault/data"
sudo chmod 700 "${PROJECT_DIRECTORY}/vault/data"

# --------------------------------------------------
# Start Vault
# --------------------------------------------------

echo "Starting Vault..."

docker compose \
    -f "${VAULT_COMPOSE}" \
    up -d

echo "Waiting for Vault..."

for ATTEMPT in $(seq 1 30); do
    if curl \
        --silent \
        --output /dev/null \
        "${VAULT_ADDRESS}/v1/sys/health"; then
        break
    fi

    if [[ "${ATTEMPT}" -eq 30 ]]; then
        echo "Error: Vault did not become reachable."
        docker compose -f "${VAULT_COMPOSE}" logs --tail=100
        exit 1
    fi

    sleep 2
done

# --------------------------------------------------
# Initialize Vault when necessary
# --------------------------------------------------

INITIALIZED="$(
    curl --silent \
        "${VAULT_ADDRESS}/v1/sys/init" |
        jq -r '.initialized'
)"

if [[ "${INITIALIZED}" == "false" ]]; then
    echo "Initializing Vault with five shares and threshold three..."

    docker compose \
        -f "${VAULT_COMPOSE}" \
        exec -T vault \
        vault operator init \
        -key-shares=5 \
        -key-threshold=3 \
        -format=json \
        > "${VAULT_INITIALIZATION}"

    chmod 600 "${VAULT_INITIALIZATION}"

    echo "Vault initialization information saved locally to:"
    echo "${VAULT_INITIALIZATION}"
fi

if [[ ! -s "${VAULT_INITIALIZATION}" ]]; then
    echo "Error: Vault is initialized, but the local initialization file is missing."
    echo "The file is required to unseal and configure Vault automatically."
    exit 1
fi

# --------------------------------------------------
# Unseal Vault
# --------------------------------------------------

SEALED="$(
    curl --silent \
        "${VAULT_ADDRESS}/v1/sys/seal-status" |
        jq -r '.sealed'
)"

if [[ "${SEALED}" == "true" ]]; then
    echo "Unsealing Vault..."

    for INDEX in 0 1 2; do
        UNSEAL_KEY="$(
            jq -r \
                ".unseal_keys_b64[${INDEX}]" \
                "${VAULT_INITIALIZATION}"
        )"

        docker compose \
            -f "${VAULT_COMPOSE}" \
            exec -T vault \
            vault operator unseal "${UNSEAL_KEY}" \
            >/dev/null
    done

    unset UNSEAL_KEY
fi

ROOT_TOKEN="$(
    jq -r '.root_token' "${VAULT_INITIALIZATION}"
)"

if [[ -z "${ROOT_TOKEN}" || "${ROOT_TOKEN}" == "null" ]]; then
    echo "Error: Root token is missing from the initialization file."
    exit 1
fi

# --------------------------------------------------
# Enable KV v2
# --------------------------------------------------

echo "Configuring the Vault KV v2 secrets engine..."

if ! docker compose \
    -f "${VAULT_COMPOSE}" \
    exec -T \
    -e VAULT_TOKEN="${ROOT_TOKEN}" \
    vault vault secrets list -format=json |
    jq -e 'has("kv/")' >/dev/null; then

    docker compose \
        -f "${VAULT_COMPOSE}" \
        exec -T \
        -e VAULT_TOKEN="${ROOT_TOKEN}" \
        vault vault secrets enable \
        -path=kv kv-v2
fi

# --------------------------------------------------
# Store database credentials
# --------------------------------------------------

if docker compose \
    -f "${VAULT_COMPOSE}" \
    exec -T \
    -e VAULT_TOKEN="${ROOT_TOKEN}" \
    vault vault kv get \
    kv/secure-fullstack \
    >/dev/null 2>&1; then

    echo "Existing database credentials found in Vault."

else
    echo "Generating and storing database credentials..."

    DATABASE_PASSWORD="$(
        openssl rand -hex 24
    )"

    docker compose \
        -f "${VAULT_COMPOSE}" \
        exec -T \
        -e VAULT_TOKEN="${ROOT_TOKEN}" \
        vault vault kv put \
        kv/secure-fullstack \
        DB_HOST="database" \
        DB_PORT="5432" \
        DB_NAME="taskdb" \
        DB_USER="taskuser" \
        DB_PASSWORD="${DATABASE_PASSWORD}" \
        >/dev/null

    unset DATABASE_PASSWORD
fi

# --------------------------------------------------
# Upload policy and create restricted token
# --------------------------------------------------

echo "Creating the restricted application policy..."

docker compose \
    -f "${VAULT_COMPOSE}" \
    exec -T \
    -e VAULT_TOKEN="${ROOT_TOKEN}" \
    vault vault policy write \
    secure-fullstack-read - \
    < "${PROJECT_DIRECTORY}/vault/app-policy.hcl" \
    >/dev/null

echo "Creating the restricted application token..."

docker compose \
    -f "${VAULT_COMPOSE}" \
    exec -T \
    -e VAULT_TOKEN="${ROOT_TOKEN}" \
    vault vault token create \
    -orphan \
    -policy="secure-fullstack-read" \
    -ttl="720h" \
    -renewable=true \
    -field=token \
    > "${VAULT_TOKEN_FILE}"

chmod 600 "${VAULT_TOKEN_FILE}"

unset ROOT_TOKEN

# --------------------------------------------------
# Build and start the application
# --------------------------------------------------

echo "Building and starting the application..."

docker compose up -d --build

echo "Waiting for the frontend..."

APPLICATION_READY="false"

for ATTEMPT in $(seq 1 30); do
    if curl \
        --silent \
        --show-error \
        --fail \
        http://127.0.0.1:8080/ \
        >/dev/null 2>&1; then

        APPLICATION_READY="true"
        break
    fi

    sleep 2
done

docker compose ps

if [[ "${APPLICATION_READY}" != "true" ]]; then
    echo "Error: Application did not become healthy."
    docker compose logs --tail=100
    exit 1
fi

echo
echo "=========================================="
echo "Setup completed successfully"
echo "=========================================="
echo "Application: http://localhost:8080"
echo "Vault UI:    http://localhost:8200"
echo
echo "Vault keys are stored locally in:"
echo "${VAULT_INITIALIZATION}"
echo
echo "Do not commit the .local directory or vault/token."
