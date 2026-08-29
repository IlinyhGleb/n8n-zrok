# n8n + zrok

Docker Compose setup for running [n8n](https://n8n.io/) together with [zrok](https://zrok.io/).

The zrok container creates a public URL for the n8n instance. The URL is written to a shared `zrok-url` file. The n8n container waits for this file, reads the URL, and uses it for its external URL configuration.

## Architecture

```text
                         Internet
                            │
                            ▼
                  ┌──────────────────┐
                  │       zrok       │
                  │                  │
                  │ public share     │
                  └────────┬─────────┘
                           │
                           │ HTTP
                           ▼
                  ┌──────────────────┐
                  │       n8n         │
                  │      :5678        │
                  └────────┬─────────┘
                           │
                    local port 5678
                           │
                           ▼
                       Host :5678
```

The two containers communicate through the private `zrok-n8n` Docker network.

zrok uses:

```text
http://n8n:5678
```

as its share target.

The public zrok URL is stored in the shared directory:

```text
zrok-shared/
├── zrok.log
└── zrok-url
```

## How it works

The startup sequence is:

```text
1. Start zrok
       │
       ▼
2. Remove old zrok-url
       │
       ▼
3. Create the zrok public share
       │
       ▼
4. Extract the generated public URL
       │
       ▼
5. Atomically write zrok-url
       │
       ▼
6. n8n waits for zrok-url
       │
       ▼
7. n8n sets N8N_EDITOR_BASE_URL
   and N8N_WEBHOOK_URL
       │
       ▼
8. Start n8n
```

This prevents n8n from using a stale URL from a previous zrok session.

## Requirements

* Docker
* Docker Compose
* A zrok environment configuration
* Access to the `ghcr.io/ilinyhgleb/zrok-share` image

## Configuration

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

The shared directory is mounted into both containers:

```text
./zrok-shared
    ↓
zrok: /home/ziggy/shared
n8n:  /shared
```

## Start

Create the persistent directories:

```bash
mkdir -p zrok-shared
mkdir -p n8n-data
```

Start the stack:

```bash
docker compose up -d
```

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

## Stop

Stop the containers:

```bash
docker compose down
```

The bind-mounted data remains on the host.

To remove the containers and their associated network:

```bash
docker compose down
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
docker compose up -d
```

For a stable deployment, use a versioned image tag instead of `dev`.

## Project structure

```text
n8n-zrok/
├── docker-compose.yml
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

Add them to `.gitignore`:

```gitignore
zrok2/environment.json
zrok-shared/
n8n-data/
```

## TrueNAS

The same architecture can be deployed as a TrueNAS custom application.

The local bind mounts correspond naturally to TrueNAS datasets:

```text
/mnt/apps/configs/n8n-zrok/zrok2
        ↓
/home/ziggy/.zrok2

/mnt/apps/configs/n8n-zrok/shared
        ↓
/home/ziggy/shared

/mnt/apps/configs/n8n-zrok/n8n
        ↓
/home/node/.n8n
```

The zrok shared directory must be writable by the `ziggy` user used by the zrok image.

The n8n container mounts the shared directory read-only because it only needs to read the generated URL.

## License

MIT
