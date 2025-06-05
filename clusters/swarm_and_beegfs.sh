#!/bin/bash

# Use: ./full_cluster_setup.sh [manager|worker] <MANAGER_IP>

set -e

ROLE=$1
MANAGER_IP=$2

if [[ "$1" == "--undo" ]]; then
  echo "[INFO] Undoing all cluster setup on $(hostname)..."

  # Leave Swarm if part of one
  if docker info | grep -q 'Swarm: active'; then
    echo "[INFO] Leaving Docker Swarm..."
    docker swarm leave --force || true
  fi

  # Stop and disable BeeGFS services
  echo "[INFO] Stopping and disabling BeeGFS services..."
  systemctl disable --now beegfs-mgmtd beegfs-meta beegfs-storage beegfs-client beegfs-helperd 2>/dev/null || true

  # Unmount BeeGFS mount
  echo "[INFO] Unmounting BeeGFS mount..."
  umount /mnt/beegfs 2>/dev/null || true
  sed -i '/\/mnt\/beegfs/d' /etc/fstab

  # Remove BeeGFS directories
  echo "[INFO] Removing BeeGFS data directories..."
  rm -rf /data/beegfs /mnt/beegfs

  # Optionally remove BeeGFS packages
  echo "[INFO] Removing BeeGFS packages..."
  apt-get purge -y beegfs-* 2>/dev/null || true
  apt-get autoremove -y

  # Optionally remove Docker packages
  echo "[INFO] Removing Docker..."
  systemctl disable --now docker
  apt-get purge -y docker-ce docker-ce-cli containerd.io 2>/dev/null || true
  apt-get autoremove -y

  # Remove BeeGFS repo
  rm -f /etc/apt/sources.list.d/beegfs.list
  apt-key del "$(apt-key list | grep -B 1 'BeeGFS' | head -n1 | awk '{print $2}')" 2>/dev/null || true

  echo "[DONE] Undo complete."
  exit 0
fi
if [[ "$ROLE" != "manager" && "$ROLE" != "worker" ]]; then
  echo "Usage: $0 [manager|worker] <MANAGER_IP (required for worker)>"
  exit 1
fi

IP_ADDR=$(hostname -I | awk '{print $1}')

echo "[INFO] Preparing system..."
sudo apt-get update
sudo apt-get install -y curl gnupg lsb-release apt-transport-https ca-certificates linux-headers-$(uname -r)

# Docker installing
echo "[INFO] Installing Docker..."
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

sudo systemctl enable docker
sudo systemctl start docker

# Docker Swarm
if [ "$ROLE" == "manager" ]; then
  echo "[INFO] Initializing Docker Swarm..."
  docker swarm init --advertise-addr "$IP_ADDR"
  docker swarm join-token worker > /tmp/swarm_worker_token.sh
  docker swarm join-token manager > /tmp/swarm_manager_token.sh
else
  echo "[INFO] Joining Docker Swarm..."
  if [ -z "$MANAGER_IP" ]; then
    echo "[ERROR] Manger ip is required."
    exit 1
  fi
  JOIN_TOKEN=$(ssh "$MANAGER_IP" "docker swarm join-token -q worker")
  docker swarm join --token "$JOIN_TOKEN" "$MANAGER_IP:2377"
fi

# BeeGFS repo
echo "[INFO] Adding BeeGFS repositories..."
echo "deb http://www.beegfs.io/release/beegfs_7_3/debian/ beegfs non-free" | sudo tee /etc/apt/sources.list.d/beegfs.list
wget -qO - http://www.beegfs.io/release/beegfs_7_3/gpg/BEGFS-GPG-KEY | sudo apt-key add -
sudo apt-get update

# BeeGFS Manager + Metadata on manager
if [ "$ROLE" == "manager" ]; then
  echo "[INFO] Installing BeeGFS management and metadata..."
  sudo apt-get install -y beegfs-mgmtd beegfs-meta

  sudo mkdir -p /data/beegfs/mgmtd
  sudo mkdir -p /data/beegfs/meta

  sudo sed -i "s|^storeMgmtdDirectory.*|storeMgmtdDirectory = /data/beegfs/mgmtd|" /etc/beegfs/beegfs-mgmtd.conf
  sudo sed -i "s|^storeMetaDirectory.*|storeMetaDirectory = /data/beegfs/meta|" /etc/beegfs/beegfs-meta.conf
  sudo sed -i "s|^sysMgmtdHost.*|sysMgmtdHost = localhost|" /etc/beegfs/beegfs-meta.conf

  sudo systemctl enable beegfs-mgmtd beegfs-meta
  sudo systemctl start beegfs-mgmtd beegfs-meta
fi

# BeeGFS Storage on worker
if [ "$ROLE" == "worker" ]; then
  echo "[INFO] Installing BeeGFS storage..."
  sudo apt-get install -y beegfs-storage

  sudo mkdir -p /data/beegfs/storage
  sudo sed -i "s|^storeStorageDirectory.*|storeStorageDirectory = /data/beegfs/storage|" /etc/beegfs/beegfs-storage.conf
  sudo sed -i "s|^sysMgmtdHost.*|sysMgmtdHost = $MANAGER_IP|" /etc/beegfs/beegfs-storage.conf

  sudo systemctl enable beegfs-storage
  sudo systemctl start beegfs-storage
fi

# BeeGFS Client on all nodes
echo "[INFO] Installing BeeGFS client..."
sudo apt-get install -y beegfs-client beegfs-helperd beegfs-utils

sudo sed -i "s|^sysMgmtdHost.*|sysMgmtdHost = $MANAGER_IP|" /etc/beegfs/beegfs-client.conf
sudo sed -i "s|^buildBeeGFSModulesFromSources.*|buildBeeGFSModulesFromSources = true|" /etc/beegfs/beegfs-client-autobuild.conf

sudo systemctl enable beegfs-helperd beegfs-client
sudo systemctl start beegfs-helperd beegfs-client

# BeeGFS Mountpoint
echo "[INFO] Making and mounting mountpoint..."
sudo mkdir -p /mnt/beegfs
echo "/mnt/beegfs /etc/beegfs/beegfs-client.conf beegfs defaults 0 0" | sudo tee -a /etc/fstab
sudo mount /mnt/beegfs || echo "[WARN] Mount failed, check client logs."

echo "[DONE] Setup completed for role: $ROLE op $IP_ADDR"