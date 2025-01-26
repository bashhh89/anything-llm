#!/bin/bash
# Your entrypoint script content here

# Ensure the script is run as root
if [ "$(id -u)" != "0" ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Check for Linux OS (not macOS or inside a Docker container)
if [ "$(uname)" = "Darwin" ]; then
    echo "This script must be run on Linux" >&2
    exit 1
fi

if [ -f /.dockerenv ]; then
    echo "This script must be run on a native Linux host" >&2
    exit 1
fi

# Check for occupied ports
if ss -tulnp | grep ':80 ' >/dev/null; then
    echo "Error: Port 80 is already in use" >&2
    exit 1
fi

if ss -tulnp | grep ':443 ' >/dev/null; then
    echo "Error: Port 443 is already in use" >&2
    exit 1
fi

# Function to check if a command exists
command_exists() {
  command -v "$@" > /dev/null 2>&1
}

# Install Docker if it is not installed
if command_exists docker; then
  echo "Docker already installed"
else
  curl -sSL https://get.docker.com | sh
fi

# Initialize Docker Swarm
docker swarm leave --force 2>/dev/null

get_ip() {
    # Try to get IPv4
    local ipv4=$(curl -4s https://ifconfig.io 2>/dev/null)

    if [ -n "$ipv4" ]; then
        echo "$ipv4"
    else
        # Try to get IPv6
        local ipv6=$(curl -6s https://ifconfig.io 2>/dev/null)
        if [ -n "$ipv6" ]; then
            echo "$ipv6"
        fi
    fi
}

advertise_addr="${ADVERTISE_ADDR:-$(get_ip)}"

docker swarm init --advertise-addr $advertise_addr

if [ $? -ne 0 ]; then
    echo "Error: Failed to initialize Docker Swarm" >&2
    exit 1
fi

docker network rm -f dokploy-network 2>/dev/null
docker network create --driver overlay --attachable dokploy-network

echo "Network created"

mkdir -p /etc/dokploy

chmod 777 /etc/dokploy

# Pull and deploy Dokploy
docker pull dokploy/dokploy:latest
docker service create \
  --name dokploy \
  --replicas 1 \
  --network dokploy-network \
  --mount type=bind,source=/var/run/docker.sock,target=/var/run/docker.sock \
  --mount type=bind,source=/etc/dokploy,target=/etc/dokploy \
  --publish published=3000,target=3000,mode=host \
  --update-parallelism 1 \
  --update-order stop-first \
  -e PORT=3000 \
  -e TRAEFIK_SSL_PORT=444 \
  -e TRAEFIK_PORT=81 \
  -e ADVERTISE_ADDR=$advertise_addr \
  dokploy/dokploy:latest

# Output success message
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
NC="\033[0m" # No Color
printf "${GREEN}Congratulations, Dokploy is installed!${NC}\n"
printf "${BLUE}Wait 15 seconds for the server to start${NC}\n"
printf "${YELLOW}Please go to http://${advertise_addr}:3000${NC}\n\n"
