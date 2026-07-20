#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f .env ]; then
    echo "ERROR: .env does not exist."
    echo "Create it:  cp .env.example .env  &&  nano .env"
    exit 1
fi

echo "==> Updating system"
apt-get update

if ! command -v docker >/dev/null 2>&1; then
    echo "==> Installing Docker (official repo)"
    apt-get install -y ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
        > /etc/apt/sources.list.d/docker.list

    apt-get update
    apt-get install -y \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin
else
    echo "==> Docker is already installed, skipping"
fi

systemctl enable docker
systemctl start docker

echo "==> Starting monitoring stack"
docker compose pull
docker compose up -d

echo ""
echo "DONE"
echo ""
echo "Check:"
echo "  docker compose ps"
echo "  docker compose logs -f"
