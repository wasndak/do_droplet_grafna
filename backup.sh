#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

DATE=$(date +"%Y-%m-%d-%H%M")
PROJECT=$(basename "$(pwd)")

mkdir -p backups

for VOLUME in influx-data-v1 grafana-data; do
    echo "==> Backing up ${PROJECT}_${VOLUME}"
    docker run --rm \
        -v "${PROJECT}_${VOLUME}":/data:ro \
        -v "$(pwd)/backups":/backup \
        ubuntu \
        tar czf "/backup/${VOLUME}-${DATE}.tar.gz" -C /data .
done

echo "Backup created in ./backups"
