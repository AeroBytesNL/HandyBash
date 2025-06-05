#!/bin/bash

# Use: ./full_cluster_setup.sh [manager|worker] <MANAGER_IP>

set -e

ROLE=$1
MANAGER_IP=$2

if [[ "$1" == "--undo" ]]; then
  echo "[INFO] Undoing all cluster setup on $(hostname)..."

  # Leave Swarm if part of one
  if docker info 2>/dev/null | grep -q 'Swarm: active'; then
    echo "[INFO] Leaving Docker Swarm..."
    # Attempt to leave gracefully first, then force if needed
    docker swarm leave || docker swarm leave --force
  fi

  # Stop and disable BeeGFS services (order matters for cleanup)
  echo "[INFO] Stopping and disabling BeeGFS services..."
  systemctl disable --now beegfs-client beegfs-helperd 2>/dev/null || true
  systemctl disable --now beegfs-meta beegfs-storage 2>/dev/null || true
  systemctl disable --now beegfs-mgmtd 2>/dev/null || true


  # Unmount BeeGFS mount
  echo "[INFO] Unmounting BeeGFS mount..."
  if mountpoint -q /mnt/beegfs; then
    umount /mnt/beegfs
  fi
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
  systemctl disable --now docker 2>/dev/null || true
  apt-get purge -y docker-ce docker-ce-cli containerd.io 2>/dev/null || true
  apt-get autoremove -y

  # Remove BeeGFS repo and GPG key
  echo "[INFO] Removing BeeGFS repository and GPG key..."
  rm -f /etc/apt/sources.list.d/beegfs.list
  rm -f /etc/apt/trusted.gpg.d/beegfs.asc # Use the new method for GPG key cleanup
  apt-get update # Update apt after removing repos

  echo "[DONE] Undo complete."
  exit 0
fi

# --- Input Validation ---
if [[ "$ROLE" != "manager" && "$ROLE" != "worker" ]]; then
  echo "Usage: $0 [manager|worker] <MANAGER_IP (required for worker)>"
  exit 1
fi

if [[ "$ROLE" == "worker" && -z "$MANAGER_IP" ]]; then
  echo "[ERROR] For worker role, MANAGER_IP is required."
  echo "Usage: $0 worker <MANAGER_IP>"
  exit 1
fi

IP_ADDR=$(hostname -I | awk '{print $1}')
if [ -z "$IP_ADDR" ]; then
    echo "[ERROR] Could not determine local IP address. Exiting."
    exit 1
fi


echo "[INFO] Preparing system..."
sudo apt-get update
sudo apt-get install -y curl gnupg lsb-release apt-transport-https ca-certificates linux-headers-"$(uname -r)"

# --- Docker Installation ---
echo "[INFO] Installing Docker..."
# Ensure /usr/share/keyrings exists
sudo mkdir -p /usr/share/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker.gpg
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io

sudo systemctl enable docker
sudo systemctl start docker

# --- Docker Swarm Configuration ---
if [ "$ROLE" == "manager" ]; then
  echo "[INFO] Initializing Docker Swarm..."
  # Check if already in a swarm to avoid errors
  if ! docker info 2>/dev/null | grep -q 'Swarm: active'; then
    docker swarm init --advertise-addr "$IP_ADDR"
    echo "[INFO] Docker Swarm Manager initialized."
    echo "Worker join token: "
    docker swarm join-token worker
    echo "Manager join token (for adding more managers): "
    docker swarm join-token manager
  else
    echo "[INFO] Already part of a Docker Swarm. Skipping initialization."
  fi
else # ROLE == "worker"
  echo "[INFO] Joining Docker Swarm..."
  # Check if already in a swarm
  if ! docker info 2>/dev/null | grep -q 'Swarm: active'; then
    JOIN_TOKEN=$(ssh "$MANAGER_IP" "docker swarm join-token -q worker")
    docker swarm join --token "$JOIN_TOKEN" "$MANAGER_IP:2377"
  else
    echo "[INFO] Already part of a Docker Swarm. Skipping join."
  fi
fi

# --- BeeGFS Repository Setup ---
echo "[INFO] Adding BeeGFS repositories..."
# Ensure the new GPG key location is used
sudo wget https://www.beegfs.io/release/beegfs_8.0/gpg/GPG-KEY-beegfs -O /etc/apt/trusted.gpg.d/beegfs.asc
sudo wget https://www.beegfs.io/release/beegfs_8.0/dists/beegfs-jammy.list \
-O /etc/apt/sources.list.d/beegfs.list
sudo apt-get update # Use sudo apt-get for consistency

# --- BeeGFS Manager + Metadata (on manager node) ---
if [ "$ROLE" == "manager" ]; then
  echo "[INFO] Installing BeeGFS management and metadata..."
  sudo apt-get install -y beegfs-mgmtd beegfs-meta beegfs-utils # Add utils for consistency

  sudo mkdir -p /data/beegfs/mgmtd
  sudo mkdir -p /data/beegfs/meta

  # Initialize services FIRST to create config files
  echo "[INFO] Initializing BeeGFS management service..."
  sudo /opt/beegfs/sbin/beegfs-setup-mgmtd -p /data/beegfs/mgmtd
  echo "[INFO] Initializing BeeGFS metadata service..."
  sudo /opt/beegfs/sbin/beegfs-setup-meta -p /data/beegfs/meta -m "$IP_ADDR" # Metadata connects to its own manager IP

  # Now modify the generated config files
  sudo sed -i "s|^sysMgmtdHost.*|sysMgmtdHost = $IP_ADDR|" /etc/beegfs/beegfs-meta.conf

  sudo systemctl enable beegfs-mgmtd beegfs-meta
  sudo systemctl start beegfs-mgmtd beegfs-meta
fi

# --- BeeGFS Storage (on worker node) ---
if [ "$ROLE" == "worker" ]; then
  echo "[INFO] Installing BeeGFS storage..."
  sudo apt-get install -y beegfs-storage beegfs-utils

  sudo mkdir -p /data/beegfs/storage

  # Initialize service FIRST to create config file
  echo "[INFO] Initializing BeeGFS storage service..."
  sudo /opt/beegfs/sbin/beegfs-setup-storage -p /data/beegfs/storage -m "$MANAGER_IP"

  # No need for extra sed for storeStorageDirectory if setup command handles it.
  # But ensure sysMgmtdHost points to the actual manager
  sudo sed -i "s|^sysMgmtdHost.*|sysMgmtdHost = $MANAGER_IP|" /etc/beegfs/beegfs-storage.conf

  sudo systemctl enable beegfs-storage
  sudo systemctl start beegfs-storage
fi

# --- BeeGFS Client (on all nodes) ---
echo "[INFO] Installing BeeGFS client..."
sudo apt-get install -y beegfs-client beegfs-helperd beegfs-utils libbeegfs-ib # libbeegfs-ib for RDMA support if needed

# Ensure client config exists. The package should create it.
if [ ! -f /etc/beegfs/beegfs-client.conf ]; then
    echo "[ERROR] /etc/beegfs/beegfs-client.conf not found after package installation. Exiting."
    exit 1
fi
# Configure client to connect to the manager
sudo sed -i "s|^sysMgmtdHost.*|sysMgmtdHost = $MANAGER_IP|" /etc/beegfs/beegfs-client.conf
# Enable autobuilding of kernel modules (good for varying kernels)
sudo sed -i "s|^buildBeeGFSModulesFromSources.*|buildBeeGFSModulesFromSources = true|" /etc/beegfs/beegfs-client-autobuild.conf

# Start helperd first, it's responsible for managing the client module
sudo systemctl enable beegfs-helperd
sudo systemctl start beegfs-helperd

# BeeGFS client service usually just loads the module, helperd manages it.
# Check status of helperd and the module.
# The client module build can take a moment.
echo "[INFO] Waiting for BeeGFS client module to build and load (this might take a moment)..."
sudo /etc/init.d/beegfs-client rebuild || true # Run rebuild, but don't fail if it temporarily errors

# BeeGFS Mountpoint
echo "[INFO] Making and mounting mountpoint..."
sudo mkdir -p /mnt/beegfs

# Check if mount point already exists in fstab to avoid duplicates
if ! grep -q "/mnt/beegfs" /etc/fstab; then
  # Use BeeGFS client config for mounting if not explicitly set in beegfs-client.conf
  # The second argument to mount.beegfs (in fstab) can be the config file.
  echo "$MANAGER_IP:/ /mnt/beegfs beegfs defaults 0 0" | sudo tee -a /etc/fstab
  # A more robust fstab entry might explicitly specify the client config file:
  # echo "/mnt/beegfs /etc/beegfs/beegfs-client.conf beegfs defaults 0 0" | sudo tee -a /etc/fstab
else
  echo "[INFO] /mnt/beegfs already in /etc/fstab. Skipping addition."
fi

# Attempt to mount now
sudo mount /mnt/beegfs || { echo "[WARN] Mount failed, check client logs (dmesg, journalctl -u beegfs-helperd)."; }

echo "[DONE] Setup completed for role: $ROLE on $IP_ADDR"