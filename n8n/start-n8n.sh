#!/bin/sh

set -u

if [ "${1:-start}" = "worker" ]; then
    echo "Starting n8n worker..."
    exec n8n worker
fi

ZROK_URL_FILE="/home/node/.n8n-files/zrok-url"

echo "Waiting for zrok URL..."

while [ ! -s "$ZROK_URL_FILE" ]; do
    sleep 1
done

ZROK_URL="$(cat "$ZROK_URL_FILE")"

if [ -z "$ZROK_URL" ]; then
    echo "ERROR: zrok URL is empty."
    exit 1
fi

echo "Using zrok URL: $ZROK_URL"

export N8N_EDITOR_BASE_URL="$ZROK_URL"
export N8N_WEBHOOK_URL="$ZROK_URL"

exec n8n start
