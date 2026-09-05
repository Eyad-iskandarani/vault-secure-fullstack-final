# Vault-Secured Full-Stack Application — Project Documentation

This university project demonstrates a secure, containerized full-stack application with automated deployment and security scanning. It uses a Flask backend, PostgreSQL database, Nginx frontend, HashiCorp Vault for secrets, Docker Compose, GitHub Actions, and GHCR.

## Architecture

The application stack contains exactly three services:

1. **Frontend** – Nginx serves the web interface on port `8080` and proxies API requests to the backend.
2. **Backend** – Flask and Gunicorn provide the task-management REST API on port `5000` inside the Docker network.
3. **Database** – PostgreSQL stores the application tasks.

Vault runs separately on port `8200`. Before the database and backend start, their entrypoint scripts retrieve the required database credentials from Vault. The credentials are not written directly in the application Compose file or committed in an `.env` file.

## How the System Works

### Container startup flow

1. The separate Vault Compose project starts the Vault server and attaches it to `secure-fullstack-network` with the hostname `vault`.
2. The database container reads its restricted token from `/run/secrets/vault_token`.
3. `vault-postgres-entrypoint.sh` requests the secret from `http://vault:8200/v1/kv/data/secure-fullstack`.
4. The script exports the returned values as PostgreSQL initialization variables and starts the official PostgreSQL entrypoint.
5. Docker waits until PostgreSQL becomes healthy.
6. The backend performs the same Vault request through `vault_entrypoint.py`, places the values only in the backend process environment, and starts Gunicorn.
7. Docker waits for the backend health endpoint before starting the frontend.
8. Nginx serves the website on port `8080`.

The Vault token is mounted read-only. The application never receives the root token or unseal keys.

### Application request flow

When a user creates a task, JavaScript sends a JSON request to `/api/tasks`. Nginx forwards the request to `backend:5000`. Flask validates the input and executes a parameterized PostgreSQL query, helping prevent SQL injection. PostgreSQL stores the task and the backend returns JSON to the browser. The same API supports listing, completing, and deleting tasks.

The main API routes are:

| Method | Route | Purpose |
|---|---|---|
| `GET` | `/health` | Check backend and database health |
| `GET` | `/api/tasks` | Retrieve all tasks |
| `POST` | `/api/tasks` | Create a task |
| `PATCH` | `/api/tasks/{id}` | Change task completion status |
| `DELETE` | `/api/tasks/{id}` | Delete a task |

### Service dependencies

Docker Compose health checks control the startup order:

```text
Vault available → Database healthy → Backend healthy → Frontend starts
```

Vault remains a separate infrastructure service, so the application Compose file still contains exactly the three required services.

## Project Structure

```text
.
├── backend/
│   ├── app.py
│   ├── vault_entrypoint.py
│   ├── requirements.txt
│   └── Dockerfile
├── database/
│   ├── vault-postgres-entrypoint.sh
│   └── Dockerfile
├── frontend/
│   ├── index.html
│   ├── app.js
│   ├── style.css
│   ├── nginx.conf
│   └── Dockerfile
├── vault/
│   ├── config.hcl
│   ├── app-policy.hcl
│   ├── docker-compose.yaml
│   └── data/
├── .github/workflows/
│   ├── build-deploy.yml
│   └── security-scanning.yml
├── docker-compose.yaml
├── setup-project.sh
└── .gitignore
```

## Important Files

- `backend/app.py`: Flask REST API and task CRUD operations.
- `backend/vault_entrypoint.py`: retrieves database variables from Vault and starts Gunicorn.
- `database/vault-postgres-entrypoint.sh`: retrieves PostgreSQL initialization credentials from Vault before starting PostgreSQL.
- `frontend/nginx.conf`: serves the frontend and forwards `/api/` requests to the backend.
- `docker-compose.yaml`: defines the database, backend, and frontend services.
- `vault/docker-compose.yaml`: runs the separate Vault server.
- `vault/config.hcl`: configures the Vault listener and file storage backend.
- `vault/app-policy.hcl`: permits the application token to read only `kv/data/secure-fullstack`.
- `setup-project.sh`: automates setup on a fresh Linux PC.
- `.github/workflows/build-deploy.yml`: builds images, pushes them to GHCR, and deploys the application with the self-hosted runner.
- `.github/workflows/security-scanning.yml`: runs the four required security tools and uploads their reports.

## Application Components

### Backend

The backend is a Flask REST API running behind Gunicorn:

- `app.py` creates the Flask application and PostgreSQL connection function.
- `initialize_database()` creates the `tasks` table when it does not already exist.
- `get_connection()` reads the database settings already loaded into the process environment and opens a PostgreSQL connection.
- The API validates task titles and Boolean completion values before executing a query.
- SQL values are passed as query parameters instead of being joined into SQL strings.
- `/health` runs `SELECT 1` to confirm that both the backend and database are available.

`vault_entrypoint.py` runs before Flask. It reads the restricted token from the mounted token file, contacts Vault, verifies that all five required fields exist, and exports them only to the Gunicorn process. It retries temporarily if Vault is not ready.

The backend Dockerfile installs the Python dependencies, copies only the necessary application files, creates a non-root user, exposes port `5000`, and starts the Vault entrypoint.

### Frontend

The frontend is a small HTML, CSS, and JavaScript application:

- `index.html` contains the task form, task list, and accessible status message.
- `style.css` provides the responsive page design.
- `app.js` uses the Fetch API to create, retrieve, update, and delete tasks without reloading the page.
- `nginx.conf` serves the static files and proxies `/api/` requests to `backend:5000` through the private Docker network.

Nginx also adds security headers such as `X-Content-Type-Options`, `X-Frame-Options`, `Referrer-Policy`, and a Content Security Policy. The unprivileged Nginx image listens on port `8080` without requiring a root web-server process.

### Database

The database image extends the official PostgreSQL 16 image. Its Dockerfile installs only `curl`, `jq`, and CA certificates, which are required to retrieve and parse the Vault response.

`vault-postgres-entrypoint.sh` performs the following steps:

1. Confirms that the restricted Vault token file is readable.
2. Requests the KV v2 secret from Vault with the `X-Vault-Token` header.
3. Extracts `DB_NAME`, `DB_USER`, and `DB_PASSWORD` with `jq`.
4. Exports them as the standard `POSTGRES_DB`, `POSTGRES_USER`, and `POSTGRES_PASSWORD` variables.
5. Executes the official PostgreSQL entrypoint.

The PostgreSQL data is stored in a named Docker volume, so tasks remain available when the application containers are recreated.

## Vault Secrets

The KV v2 path is:

```text
kv/secure-fullstack
```

It contains:

```text
DB_HOST
DB_PORT
DB_NAME
DB_USER
DB_PASSWORD
```

The application uses a restricted Vault token rather than the root token. Vault tokens, root credentials, unseal keys, database passwords, and runtime data are excluded from Git by `.gitignore`.

## Automated Setup on a New PC

Install Git, Docker, Docker Compose, `curl`, `jq`, and OpenSSL. Then run:

```bash
git clone https://github.com/Eyad-iskandarani/vault-secure-fullstack-final.git
cd vault-secure-fullstack-final
./setup-project.sh
```

The setup script prepares Vault storage, starts and initializes Vault, generates five unseal keys with a threshold of three, unseals Vault, enables KV v2, generates the database credentials, creates the restricted application token, and starts all three application services.

After setup:

- Application: `http://localhost:8080`
- Vault UI: `http://localhost:8200`
- Local Vault initialization file: `.local/vault-init.json`

The local initialization file must not be committed. To retrieve the locally generated root token for the Vault UI:

```bash
jq -r '.root_token' .local/vault-init.json
```

## CI/CD Workflow

The Build and Deploy workflow runs on the self-hosted GitHub Actions runner. It:

1. Checks out the repository.
2. Builds the database, backend, and frontend images.
3. Pushes the images to GitHub Container Registry (GHCR).
4. Creates the local restricted Vault token file from the GitHub Actions secret.
5. Deploys the stack with Docker Compose.
6. Verifies that the application responds successfully.

The self-hosted runner must be online, and Vault must be running and unsealed for deployment.

The images are published as:

```text
ghcr.io/eyad-iskandarani/vault-secure-fullstack-final-database
ghcr.io/eyad-iskandarani/vault-secure-fullstack-final-backend
ghcr.io/eyad-iskandarani/vault-secure-fullstack-final-frontend
```

Each build receives both a `latest` tag and a commit-SHA tag. The SHA tag identifies the exact source revision used to create an image, while `latest` is used by the deployment Compose file.

## Security Workflow

The separate security workflow executes:

- **Hadolint** – checks all Dockerfiles for security and best-practice issues.
- **Bandit** – performs Python static application security testing on the backend.
- **TruffleHog** – checks the repository and Git history for exposed credentials.
- **Trivy** – scans the database, backend, and frontend container images for vulnerabilities.

The workflow uploads one report per tool:

```text
hadolint-report.txt
bandit-report.txt
trufflehog-report.txt
trivy-report.txt
```

## Problems Solved During Implementation

### Vault repeatedly restarted

Vault reported `bind: address already in use` even though the host port was available. The HashiCorp container entrypoint automatically loaded `/vault/config`, while the Compose command also loaded the same `config.hcl` explicitly. This created two identical listeners on port `8200`. The fix was to use only:

```yaml
command:
  - server
```

### Database was unhealthy

The database entrypoint stopped because the Vault secret did not contain `DB_USER`. Adding `DB_USER=taskuser` to `kv/secure-fullstack` allowed PostgreSQL to initialize and the backend and frontend to start.

### Git and runner setup

The project was pushed through SSH after adding a new SSH public key to GitHub. A repository-specific self-hosted runner was then registered for build, scanning, and deployment jobs.

## GitHub SSH Setup

SSH authentication was configured so Git operations could be performed without entering a GitHub username on every push.

Generate an Ed25519 key:

```bash
ssh-keygen -t ed25519 -C "YOUR_GITHUB_EMAIL"
```

Press Enter to accept the default file location. Start the SSH agent and load the private key:

```bash
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

Display the public key:

```bash
cat ~/.ssh/id_ed25519.pub
```

Copy the complete public-key line and add it under:

```text
GitHub → Settings → SSH and GPG keys → New SSH key
```

Only the `.pub` key is copied to GitHub. The private `~/.ssh/id_ed25519` file must never be shared or committed.

Test authentication:

```bash
ssh -T git@github.com
```

Configure this repository to use SSH and push it:

```bash
git remote set-url origin git@github.com:Eyad-iskandarani/vault-secure-fullstack-final.git
git push -u origin main
```

SSH is required for pushing from that PC, but a public repository can be cloned for demonstration without an SSH key:

```bash
git clone https://github.com/Eyad-iskandarani/vault-secure-fullstack-final.git
```

## How to Push a Project to GitHub

Create an empty repository on GitHub first. Then open the local project directory:

```bash
cd /path/to/your/project
```

For a project that is not already a Git repository, initialize it and select the `main` branch:

```bash
git init
git branch -M main
```

Connect the local project to the GitHub repository using SSH:

```bash
git remote add origin git@github.com:USERNAME/REPOSITORY.git
```

Check the files that have changed:

```bash
git status
```

Stage the files that should be included in the commit:

```bash
git add .
```

Create a commit containing the staged files:

```bash
git commit -m "Initial project commit"
```

Push the `main` branch to GitHub for the first time:

```bash
git push -u origin main
```

The `-u` option connects the local `main` branch to `origin/main`. For later changes, the shorter process is:

```bash
git status
git add .
git commit -m "Describe the changes"
git push
```

Useful checking commands are:

```bash
git remote -v
git branch --show-current
git log --oneline -5
```

- `git remote -v` shows the connected GitHub repository.
- `git branch --show-current` shows the active branch.
- `git log --oneline -5` shows the five most recent commits.

Files containing passwords, tokens, private keys, or runtime data should be added to `.gitignore` before running `git add .`.

## Verification

Check all application containers:

```bash
docker compose ps
```

Check Vault:

```bash
docker compose -f vault/docker-compose.yaml exec vault vault status
```

Test the application:

```bash
curl -s -o /dev/null -w "Frontend: %{http_code}\n" http://localhost:8080/
curl -s -o /dev/null -w "API: %{http_code}\n" http://localhost:8080/api/tasks
```

Successful HTTP responses should return status `200`, and Vault should show `Initialized: true` and `Sealed: false`.

## Final Result

The project provides a working full-stack application, independent containers, Vault-managed database credentials, automated GHCR build and deployment, and a separate four-tool security pipeline with downloadable reports.
