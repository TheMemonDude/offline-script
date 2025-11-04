#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -eEo pipefail

iface=$(ip -o route get 8.8.8.8 | awk '{print $5}' | head -1) && \
mac=$(ip link show "$iface" | grep -i "link/ether" | awk '{print $2}')
echo "$iface → $mac"

curl -fsSL https://get.docker.com | sudo sh && \
sudo usermod -aG docker $USER && \
sudo systemctl enable --now docker
