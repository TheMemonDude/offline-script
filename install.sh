#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -eEo pipefail

# INTERFACE=$(ip -o route get 8.8.8.8 | awk '{print $5}' | head -1) && \
INTERFACE=$(ip -o -4 route show to default | awk '{print $5}' | head -1) && \
MAC_ADDR=$(ip link show "$INTERFACE" | grep -i "link/ether" | awk '{print $2}')

# Network
APP_DOMAIN="$domain"
STATIC_IP="192.168.1.100"
GATEWAY="192.168.1.1"
LAN_NETWORK="192.168.1.0/24"

# File Extraction
BZ2_FILE="app.tar.bz2"
IMAGE_TAR_FILE="app.tar"

# App
APP_IMAGE="demo_offline_app:latest"
APP_CONTAINER="app"
APP_PORT=8080

# DB
DB_IMAGE="postgres:18"
DB_CONTAINER="postgres-db"
DB_PORT=5432
DB_USER="$dbuser"
DB_NAME="$dbname"
DB_PASSWORD="$dbpass"

# Proxy
CADDY_CONTAINER="caddy-proxy"

# WEB_USER="admin"
# WEB_PASS="SecurePass2025!"

# Backups
DB_DATA="/opt/myapp/db-data"
APP_DATA="/opt/myapp/app-data"
SSL_DIR="/opt/myapp/ssl"
BACKUP_DIR="/opt/myapp/backups"
CADDYFILE="/opt/myapp/Caddyfile"
HTPASSWD="/opt/myapp/.htpasswd"

DOCKER_GROUP="docker"
run_as_docker() {
  sg "$DOCKER_GROUP" -c "$*"
}

sudo apt update && sudo apt install -y git bzip2 ufw fail2ban

if ! command -v docker >/dev/null 2>&1; then
  echo "Installing Docker..."

  curl -fsSL https://get.docker.com | sudo sh

  sudo mkdir -p /etc/docker
  sudo tee /etc/docker/daemon.json > /dev/null <<'EOF'
  {
    "log-driver": "json-file",
    "log-opts": {
      "max-size": "10m",
      "max-file": "5"
    }
  }
EOF

  sudo systemctl enable --now docker && \
  sudo usermod -aG docker $USER && \
  sudo systemctl restart docker
  echo "Docker installed!"
fi

# Set Static IP
sudo tee /etc/netplan/01-static.yaml > /dev/null <<EOF
network:
  version: 2
  ethernets:
    $INTERFACE:
      dhcp4: no
      addresses: [$STATIC_IP/24]
      gateway4: $GATEWAY
      nameservers:
        addresses: [$GATEWAY]
EOF
sudo netplan apply

# Set Local Domain Host
if ! grep -q "$APP_DOMAIN" /etc/hosts; then
    echo "$STATIC_IP $APP_DOMAIN" | sudo tee -a /etc/hosts > /dev/null
fi

# Backup Dirs
sudo mkdir -p "$DB_DATA" "$APP_DATA" "$SSL_DIR" "$BACKUP_DIR"
sudo chown -R $USER:$USER "$DB_DATA" "$APP_DATA" "$SSL_DIR" "$BACKUP_DIR"

# Generate SSL Certs
if [ ! -f "$SSL_DIR/fullchain.pem" ]; then
    sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
        -keyout "$SSL_DIR/privkey.pem" \
        -out "$SSL_DIR/fullchain.pem" \
        -subj "/CN=$APP_DOMAIN"
    sudo chmod 600 "$SSL_DIR/privkey.pem"
fi

# === 7. Generate web login ===
# sudo htpasswd -cb "$HTPASSWD" "$WEB_USER" "$WEB_PASS"
# sudo chmod 640 "$HTPASSWD"

# Caddy Proxy
sudo tee "$CADDYFILE" > /dev/null <<EOF
  $APP_DOMAIN {
      reverse_proxy localhost:$APP_PORT
      tls $SSL_DIR/fullchain.pem $SSL_DIR/privkey.pem
  }
EOF

if [ ! -f "$REPO_FILE" ]; then
  echo "Downloading Application Source Code..."
  curl -L -o $BZ2_FILE "https://github.com/TheMemonDude/offline-apps/raw/refs/heads/main/demo_offline.tar.bz2"
fi

echo "Extacting App Source Code..."
bzip2 -dc $BZ2_FILE > "$IMAGE_TAR_FILE"

LOAD_OUTPUT=$(run_as_docker docker load -i "$IMAGE_TAR_FILE" 2>&1)
echo "Image Loaded: $LOAD_OUTPUT"

# === 9. DB Service ===
sudo tee /etc/systemd/system/$DB_CONTAINER.service > /dev/null <<EOF
[Unit]
Description=MyApp DB
After=docker.service
Requires=docker.service

[Service]
TimeoutStartSec=0
Restart=no
ExecStartPre=-/usr/bin/docker stop $DB_CONTAINER
ExecStartPre=-/usr/bin/docker rm $DB_CONTAINER
ExecStart=/usr/bin/docker run -d \
  --name $DB_CONTAINER \
  -e POSTGRES_PASSWORD=$DB_PASSWORD \
  -e POSTGRES_DB=$DB_NAME \
  -v $DB_DATA:/var/lib/postgresql/data/pgdata \
  -p $DB_PORT:$DB_PORT \
  --network host \
  $DB_IMAGE

[Install]
WantedBy=multi-user.target
EOF

# === 10. App Service ===
# sudo tee /etc/systemd/system/$APP_CONTAINER.service > /dev/null <<EOF
# [Unit]
# Description=Web App
# After=$DB_CONTAINER.service
# Requires=$DB_CONTAINER.service
#
# [Service]
# TimeoutStartSec=0
# Restart=always
# ExecStartPre=-/usr/bin/docker stop $APP_CONTAINER
# ExecStartPre=-/usr/bin/docker rm $APP_CONTAINER
# ExecStart=/usr/bin/docker run -d \
#   --name $APP_CONTAINER \
#   -v $APP_DATA:/app/data \
#   -e PHX_SERVER=true \
#   -e PHX_HOST=$APP_DOMAIN \
#   -e PORT=$APP_PORT \
#   -e SECRET_KEY_BASE=$(openssl rand -base64 48 | tr -d '\n') \
#   -e DATABASE_URL=ecto://postgres:$DB_PASSWORD@127.0.0.1:$DB_PORT/$DB_NAME
#   -p $APP_PORT:$APP_PORT \
#   --network host \
#   $APP_IMAGE
# ExecStop=/usr/bin/docker stop $APP_CONTAINER
#
#
# [Install]
# WantedBy=multi-user.target
# EOF

# === 11. Caddy Proxy ===
# sudo tee /etc/systemd/system/$CADDY_CONTAINER.service > /dev/null <<EOF
# [Unit]
# Description=Caddy Proxy
# After=$APP_CONTAINER.service
# Requires=$APP_CONTAINER.service
#
# [Service]
# TimeoutStartSec=0
# Restart=always
# ExecStartPre=-/usr/bin/docker stop $CADDY_CONTAINER
# ExecStartPre=-/usr/bin/docker rm $CADDY_CONTAINER
# ExecStart=/usr/bin/docker run -d \
#   --name $CADDY_CONTAINER \
#   -v $CADDYFILE:/etc/caddy/Caddyfile:ro \
#   -v $SSL_DIR:/etc/ssl/caddy:ro \
#   -p 80:80 -p 443:443 \
#   --network host \
#   caddy:2-alpine
# ExecStop=/usr/bin/docker stop $CADDY_CONTAINER
#
# [Install]
# WantedBy=multi-user.target
# EOF

# === 12. Daily Backup ===
# sudo tee /etc/cron.daily/myapp-backup > /dev/null <<'EOF'
# #!/bin/bash
# BACKUP_DIR="/opt/myapp/backups"
# DB_DATA="/opt/myapp/db-data"
# APP_DATA="/opt/myapp/app-data"
# mkdir -p "$BACKUP_DIR"
# tar -czf "$BACKUP_DIR/db-daily-$(date +%F).tar.gz" -C "$(dirname $DB_DATA)" "$(basename $DB_DATA)" 2>/dev/null || true
# tar -czf "$BACKUP_DIR/app-daily-$(date +%F).tar.gz" -C "$(dirname $APP_DATA)" "$(basename $APP_DATA)" 2>/dev/null || true
# find "$BACKUP_DIR" -name "*.tar.gz" -mtime +7 -delete
# EOF
# sudo chmod +x /etc/cron.daily/myapp-backup

# === 13. Cert Renew ===
# sudo tee /etc/cron.monthly/renew-cert > /dev/null <<EOF
# #!/bin/bash
# openssl req -x509 -nodes -days 90 -newkey rsa:2048 \
#     -keyout "$SSL_DIR/privkey.pem" \
#     -out "$SSL_DIR/fullchain.pem" \
#     -subj "/CN=$APP_DOMAIN"
# chmod 600 "$SSL_DIR/privkey.pem"
# systemctl restart $CADDY_CONTAINER
# EOF
# sudo chmod +x /etc/cron.monthly/renew-cert

# === 14. Fail2Ban ===
sudo tee /etc/fail2ban/jail.local > /dev/null <<EOF
[ssh]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

[caddy]
enabled = true
port = http,https
filter = caddy
logpath = /var/log/caddy/access.log
maxretry = 3
bantime = 3600
EOF

sudo tee /etc/fail2ban/filter.d/caddy.conf > /dev/null <<'EOF'
[Definition]
failregex = ^.*"POST /.*" 401.*$
            ^.*"GET /.*" 401.*$
ignoreregex =
EOF

sudo mkdir -p /var/log/caddy
sudo touch /var/log/caddy/access.log
sudo chown $USER:$USER /var/log/caddy/access.log

# === 15. Firewall ===
sudo ufw --force reset
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from $LAN_NETWORK to any port 80 proto tcp
sudo ufw allow from $LAN_NETWORK to any port 443 proto tcp
sudo ufw --force enable

# === 16. Enable & Start ===
sudo systemctl daemon-reload
sudo systemctl enable $DB_CONTAINER.service fail2ban
# sudo systemctl enable $DB_CONTAINER.service $APP_CONTAINER.service $CADDY_CONTAINER.service fail2ban
sudo systemctl start $DB_CONTAINER.service
# sleep 10
# sudo systemctl start $APP_CONTAINER.service
# sleep 3
# sudo systemctl start $CADDY_CONTAINER.service
sudo systemctl start fail2ban

# run_as_docker bash <<SCRIPT
#   echo "Running migrations..."
#   sleep 5  # Give app time to boot
#   docker exec $CONTAINER_NAME /app/bin/migrate
# SCRIPT

echo "Setup completed!"
