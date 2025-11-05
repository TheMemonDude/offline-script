#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -eEo pipefail

INTERFACE=$(ip -o route get 8.8.8.8 | awk '{print $5}' | head -1) && \
MAC_ADDR=$(ip link show "$INTERFACE" | grep -i "link/ether" | awk '{print $2}')

IMAGE_NAME="app.tar"
CONTAINER_NAME="app-container"
CONTAINER_PORT=4000
HOST_PORT=4000

DB_CONTAINER_NAME="postgres"
DB_CONTAINER_PORT=5432
DB_HOST_PORT=5432
DB_USER=$dbuser
DB_NAME=$dbname
DB_PASS=$dbpass

echo "checking docker"
if ! command -v docker >/dev/null 2>&1; then
  curl -fsSL https://get.docker.com | sudo sh && \
  sudo systemctl enable --now docker && \
  sudo usermod -aG docker $USER && \
  newgrp docker
fi

echo "docker installed"

echo "getting offline app image"
curl -L -o app.tar.bz2 "https://github.com/TheMemonDude/offline-apps/raw/refs/heads/main/demo_offline.tar.bz2"
bzip2 -dc app.tar.bz2 > "$IMAGE_NAME"

LOAD_OUTPUT=$(docker load -i "$IMAGE_NAME" 2>&1)
echo "$LOAD_OUTPUT"

# IMAGE_ID=$(echo "$LOAD_OUTPUT" | grep -oE 'demo_offline:[a-z]+' | head -1 || true)
IMAGE_NAME=$(echo "$LOAD_OUTPUT" | grep -oE 'Loaded image: .*' | sed 's/Loaded image: //' | head -1)

echo "Starting db container"
docker run -d \
  --name $DB_CONTAINER_NAME \
  -e POSTGRES_USER=$DB_USER \
  -e POSTGRES_PASSWORD=$DB_PASS \
  -e POSTGRES_DB=$DB_NAME \
  -p $DB_HOST_PORT:$DB_CONTAINER_PORT \
  -v app_db_data:/var/lib/postgresql/data/pgdata \
  postgres:18

echo "Starting App container"
docker run -d \
  --name $CONTAINER_NAME \
  --link $DB_CONTAINER_NAME:db \
  -p $HOST_PORT:$DB_CONTAINER_PORT \
  -e DATABASE_URL=ecto://$DB_USER:$DB_PASS@db:5432/$DB_NAME \
  -e SECRET_KEY_BASE=$(openssl rand -hex 32) \
  -e PORT=$CONTAINER_PORT \
  $IMAGE_NAME 

echo "Running migrations..."
docker exec $CONTAINER_NAME /app/bin/migrate

echo "setup completed"
