#!/bin/bash

set -e

function installDocker() {
  echo "Reinstalling Docker using official Docker repository..."
  apt-get update
  apt-get install -y ca-certificates curl gnupg lsb-release

  echo "Adding Docker GPG key..."
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/$(. /etc/os-release && echo "$ID")/gpg | \
      gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg

  echo "Adding Docker APT repository..."
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/$(. /etc/os-release && echo "$ID") \
    $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

  echo "Installing Docker CE and plugins..."
  apt-get update
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  echo "Docker installation complete!"
  docker version
}

function uninstallDocker() {
  echo "Stopping and removing all Docker services and containers..."
  docker service rm $(docker service ls -q 2>/dev/null) 2>/dev/null || true
  docker container stop $(docker ps -aq 2>/dev/null) 2>/dev/null || true
  docker container rm $(docker ps -aq 2>/dev/null) 2>/dev/null || true

  echo "Leaving Docker Swarm (if active)..."
  docker swarm leave --force 2>/dev/null || true

  echo "Purging Docker packages..."
  apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  echo "Removing Docker data and configuration..."
  rm -rf /var/lib/docker
  rm -rf /var/lib/containerd
  rm -rf /etc/docker
  rm -rf /run/docker*
  rm -rf /var/run/docker*
  rm -rf /etc/apt/sources.list.d/docker.list
  rm -f /etc/apt/keyrings/docker.gpg

  echo "Docker uninstall complete!"
}

function showUsage() {
  echo "Usage: $0 [--install | --reinstall | --uninstall]"
  exit 1
}

if [ $# -ne 1 ]; then
  showUsage
fi

case "$1" in
  --install)
    installDocker
    ;;
  --uninstall)
    uninstallDocker
    ;;
  --reinstall)
    uninstallDocker
    installDocker
    ;;
  *)
    showUsage
    ;;
esac