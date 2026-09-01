# n8n + zrok

Docker Compose setup for running [n8n](https://n8n.io/) together with [zrok](https://zrok.io/).

The stack consists of four services:

* **n8n** — workflow automation
* **PostgreSQL** — n8n database
* **Redis** — n8n queue backend
* **zrok** — public access to the n8n instance

The zrok container creates a public URL for the n8n instance. The URL is written to a shared `zrok-url` file. The n8n container waits for this file, reads the URL, and uses it for its external URL configuration.

## Architecture

```text
                         Internet
                            │
                            ▼
                  ┌──────────────────┐
                  │       zrok       │
                  │                  │
                  │  public share    │
                  └────────┬─────────┘
                           │
                           │ HTTP
                           ▼
                  ┌──────────────────┐
                  │       n8n        │
                  │      :5678       │
                  └──────┬─────┬─────┘
                         │     │
                 ┌───────┘     └───────┐
                 ▼                     ▼
          ┌──────────────┐      ┌──────────────┐
          │  PostgreSQL  │      │    Redis     │
          │     :5432    │      │     :6379    │
          └──────────────┘      └──────────────┘

                         │
                  local port 5678
                         │
                         ▼
                     Host :5678
```

All four containers communicate through the private `n8n-zrok` Docker network.

zrok uses:

```text
http://n8n:5678
```

as its share target.

n8n uses:

```text
postgres:5432
```

for PostgreSQL and:

```text
redis:6379
```

for Redis.

The public zrok URL is stored in the shared directory:

```text
zrok-shared/
├── zrok.log
└── zrok-url
```

## How it works

The startup sequence is:

```text
1. Start PostgreSQL and Redis
       │
       ▼
2. Start n8n and zrok
       │
       ▼
3. zrok removes old zrok-url
       │
       ▼
4. zrok creates the public share
       │
       ▼
5. Extract the generated public URL
       │
       ▼
6. Atomically write zrok-url
       │
       ▼
7. n8n waits for zrok-url
       │
       ▼
8. n8n sets N8N_EDITOR_BASE_URL
   and N8N_WEBHOOK_URL
       │
       ▼
9. Start n8n
```

This prevents n8n from using a stale URL from a previous zrok session.

PostgreSQL stores the n8n database, while Redis is used as the queue backend.

## Requirements

* Docker
* Docker Compose
* A zrok environment configuration
* Access to the `ghcr.io/ilinyhgleb/zrok-share` image

## Configuration

### zrok

Create the zrok configuration directory:

```bash
mkdir -p zrok2
```

Copy your zrok environment configuration into:

```text
zrok2/environment.json
```

The file is mounted read-only into the zrok container:

```text
./zrok2
    ↓
/home/ziggy/.zrok2
```

### Shared directory

The shared directory is mounted into both containers:

```text
./zrok-shared
    ↓
zrok: /home/ziggy/shared
n8n:  /shared
```

zrok writes the generated URL to:

```text
/home/ziggy/shared/zrok-url
```

n8n reads it from:

```text
/shared/zrok-url
```

### PostgreSQL password

The local Compose configuration uses the `POSTGRES_PASSWORD` environment variable.

A `.env` file is **not required**.

For example:

```bash
POSTGRES_PASSWORD='my-password' docker compose up -d
```

The password is used by both the PostgreSQL and n8n containers.

## Start

Create the persistent directories:

```bash
mkdir -p zrok-shared
mkdir -p n8n-data
```

Start the stack:

```bash
POSTGRES_PASSWORD='my-password' docker compose up -d --build
```

The local configuration builds the n8n image from the `n8n/` directory.

PostgreSQL uses a Docker-managed named volume, so no `postgres-data` directory is required in the project.

View the logs:

```bash
docker compose logs -f zrok n8n
```

A successful startup should look approximately like:

```text
zrok  | Starting zrok...
zrok  | zrok URL: https://xxxxxxxxxxxx.shares.zrok.io

n8n   | Waiting for zrok URL...
n8n   | Using zrok URL: https://xxxxxxxxxxxx.shares.zrok.io
```

The n8n web interface is available locally at:

```text
http://localhost:5678
```

The public zrok URL can be found with:

```bash
cat zrok-shared/zrok-url
```

## Verify the configuration

Check the generated URL:

```bash
cat zrok-shared/zrok-url
```

Check the n8n environment:

```bash
docker compose exec n8n env | grep '^N8N_'
```

The important variables should contain the current zrok URL:

```text
N8N_EDITOR_BASE_URL=https://xxxxxxxxxxxx.shares.zrok.io
N8N_WEBHOOK_URL=https://xxxxxxxxxxxx.shares.zrok.io
```

Check all services:

```bash
docker compose ps
```

The stack should contain:

```text
n8n
postgres
redis
zrok
```

## Database

n8n uses PostgreSQL instead of the default SQLite database.

The PostgreSQL service is configured with:

```text
Database: n8n
User:     n8n
Host:     postgres
Port:     5432
```

n8n connects to PostgreSQL using the Docker service name:

```text
postgres:5432
```

PostgreSQL is not exposed to the host.

For local development, PostgreSQL data is stored in a Docker-managed named volume:

```yaml
volumes:
  - postgres-data:/var/lib/postgresql/data
```

The volume persists when the containers are stopped or recreated.

To remove the database as well as the containers:

```bash
docker compose down -v
```

**Warning:** `docker compose down -v` deletes the PostgreSQL database.

## Redis

Redis is used as the n8n queue backend.

n8n connects to Redis using:

```text
redis:6379
```

The current configuration uses:

```text
EXECUTIONS_MODE=queue
```

Redis is not exposed to the host.

A separate n8n worker can be added later if queue-based execution needs to be scaled.

## Stop

Stop the containers:

```bash
docker compose down
```

The bind-mounted n8n and zrok data remains on the host.

The PostgreSQL data also remains because it is stored in a Docker named volume.

To remove the containers, network, and PostgreSQL volume:

```bash
docker compose down -v
```

## Update the zrok image

The zrok container uses the image:

```text
ghcr.io/ilinyhgleb/zrok-share:dev
```

Pull the latest image:

```bash
docker compose pull zrok
```

Then recreate the container:

```bash
POSTGRES_PASSWORD='my-password' docker compose up -d
```

For a stable deployment, use a versioned image tag instead of `dev`.

## Update the n8n image

The local n8n image is built from the Dockerfile:

```text
n8n/Dockerfile
```

Rebuild it with:

```bash
POSTGRES_PASSWORD='my-password' docker compose up -d --build n8n
```

The GitHub Actions workflow publishes the resulting image to:

```text
ghcr.io/ilinyhgleb/n8n-zrok
```

## Project structure

```text
n8n-zrok/
├── docker-compose.yml
├── docker-compose.truenas.yml
├── README.md
├── zrok2/
│   └── environment.json
├── zrok-shared/
├── n8n-data/
└── n8n/
    ├── Dockerfile
    └── start-n8n.sh
```

### zrok

The zrok container uses the existing:

```text
ghcr.io/ilinyhgleb/zrok-share
```

image.

No zrok source code is duplicated in this repository.

### n8n

The n8n image is extended with a small wrapper entrypoint.

The wrapper:

1. Waits for `zrok-url`.
2. Reads the public URL.
3. Sets `N8N_EDITOR_BASE_URL`.
4. Sets `N8N_WEBHOOK_URL`.
5. Starts n8n.

### PostgreSQL

PostgreSQL uses the official PostgreSQL image:

```text
postgres:17
```

For local development, its data is stored in a Docker named volume.

### Redis

Redis uses the official Redis image:

```text
redis:7
```

It is used internally by n8n and is not exposed to the host.

## Persistence

The following directories contain runtime data and should not be committed to Git:

```text
zrok-shared/
n8n-data/
```

The zrok configuration is also local configuration and should normally not be committed if it contains credentials or other sensitive information:

```text
zrok2/environment.json
```

PostgreSQL data is stored in a Docker-managed named volume locally and therefore does not appear in the project directory.

Add the local data and configuration to `.gitignore`:

```gitignore
zrok2/environment.json
zrok-shared/
n8n-data/
```

## TrueNAS

The same architecture can be deployed as a TrueNAS custom application.

The TrueNAS deployment uses:

```text
docker-compose.truenas.yml
```

Unlike the local configuration, the TrueNAS configuration uses the published n8n image:

```text
ghcr.io/ilinyhgleb/n8n-zrok:latest
```

The local configuration builds the image:

```yaml
build:
  context: ./n8n
```

The TrueNAS configuration pulls the image:

```yaml
image: ghcr.io/ilinyhgleb/n8n-zrok:latest
```

### TrueNAS datasets

Recommended directory structure:

```text
/mnt/apps/configs/n8n-zrok/
├── n8n-data/
├── postgres-data/
├── zrok-config/
└── zrok-shared/
```

The mounts are:

```text
/mnt/apps/configs/n8n-zrok/zrok-config
        ↓
/home/ziggy/.zrok2

/mnt/apps/configs/n8n-zrok/zrok-shared
        ↓
/home/ziggy/shared

/mnt/apps/configs/n8n-zrok/n8n-data
        ↓
/home/node/.n8n

/mnt/apps/configs/n8n-zrok/postgres-data
        ↓
/var/lib/postgresql/data
```

The zrok configuration is mounted read-only.

The zrok shared directory must be writable by the user used by the zrok image.

The n8n container mounts the shared directory read-only because it only needs to read the generated URL.

PostgreSQL uses a dedicated TrueNAS dataset so that its database is persistent and can be included in the TrueNAS backup strategy.

### TrueNAS networking

All services use the same private Docker network:

```text
n8n-zrok
```

The services can reach each other using their service names:

```text
n8n       → n8n:5678
postgres  → postgres:5432
redis     → redis:6379
```

n8n exposes port `5678` to the TrueNAS host:

```yaml
ports:
  - "5678:5678"
```

Therefore n8n can also be accessed from the local network using:

```text
http://<TRUENAS-IP>:5678
```

zrok should use:

```text
http://n8n:5678
```

as its target.

Do not use:

```text
http://0.0.0.0:5678
```

for container-to-container communication.

### TrueNAS permissions

The n8n container runs as:

```text
UID 1000
GID 1000
```

The `n8n-data` dataset therefore needs to be writable by UID/GID `1000:1000`.

The n8n data directory should not use `777` permissions.

The zrok configuration must be readable by the user running the zrok container, while `zrok-shared` must be writable by zrok.

The exact UID/GID used by the zrok image should be verified before configuring the corresponding TrueNAS permissions.

## GitHub Actions

GitHub Actions builds and publishes the n8n image to GitHub Container Registry:

```text
ghcr.io/ilinyhgleb/n8n-zrok
```

The workflow builds only the n8n image.

The zrok image:

```text
ghcr.io/ilinyhgleb/zrok-share
```

is maintained separately and is pulled by Docker Compose.

The local Compose configuration builds n8n from source, while the TrueNAS configuration uses the published GHCR image.

## License

MIT
