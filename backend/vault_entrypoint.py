import json
import os
import sys
import time
import urllib.error
import urllib.request


VAULT_ADDR = os.getenv("VAULT_ADDR", "http://vault:8200").rstrip("/")
VAULT_SECRET_PATH = os.getenv(
    "VAULT_SECRET_PATH",
    "kv/data/secure-fullstack",
).strip("/")

VAULT_TOKEN_FILE = os.getenv(
    "VAULT_TOKEN_FILE",
    "/run/secrets/vault_token",
)


def read_token():
    try:
        with open(VAULT_TOKEN_FILE, "r", encoding="utf-8") as token_file:
            token = token_file.read().strip()
    except OSError as error:
        raise RuntimeError(
            f"Cannot read Vault token file: {error}"
        ) from error

    if not token:
        raise RuntimeError("Vault token file is empty")

    return token


def retrieve_secrets(token):
    request = urllib.request.Request(
        f"{VAULT_ADDR}/v1/{VAULT_SECRET_PATH}",
        headers={"X-Vault-Token": token},
    )

    with urllib.request.urlopen(request, timeout=10) as response:
        payload = json.loads(response.read().decode("utf-8"))

    return payload["data"]["data"]


def load_database_secrets():
    required_variables = {
        "DB_HOST",
        "DB_PORT",
        "DB_NAME",
        "DB_USER",
        "DB_PASSWORD",
    }

    token = read_token()
    last_error = None

    for attempt in range(1, 31):
        try:
            secrets = retrieve_secrets(token)
            missing = required_variables.difference(secrets)

            if missing:
                raise RuntimeError(
                    "Vault secret is missing: "
                    + ", ".join(sorted(missing))
                )

            for variable in required_variables:
                os.environ[variable] = str(secrets[variable])

            print(
                "Backend retrieved database credentials from Vault.",
                flush=True,
            )
            return

        except (
            KeyError,
            RuntimeError,
            urllib.error.URLError,
            json.JSONDecodeError,
        ) as error:
            last_error = error
            print(
                f"Vault attempt {attempt}/30 failed: {error}",
                file=sys.stderr,
                flush=True,
            )
            time.sleep(2)

    raise RuntimeError(
        f"Unable to retrieve secrets from Vault: {last_error}"
    )


if __name__ == "__main__":
    load_database_secrets()

    os.execvp(
        "gunicorn",
        [
            "gunicorn",
            "--bind",
            "0.0.0.0:5000",
            "--workers",
            "2",
            "--access-logfile",
            "-",
            "--error-logfile",
            "-",
            "app:app",
        ],
    )
