#!/bin/bash

function install() {
  echo "Updating packages list"
  sudo apt update -y

  echo "Installing Fail2Ban package..."
  sudo apt install fail2ban -y

  echo "Enabling Fail2Ban"
  sudo systemctl enable --now fail2ban

  echo "Starting Fail2Ban"
  sudo systemctl start fail2ban

  echo "Fail2Ban installed!"
}

function uninstall() {
  echo "Stopping Fail2Ban..."
  sudo systemctl stop fail2ban || true

  echo "Removing Fail2Ban package..."
  sudo apt remove --purge fail2ban -y

  echo "Deleting configuration files..."
  sudo rm -rf /etc/fail2ban

  echo "Cleaning up unused packages..."
  sudo apt autoremove -y
  sudo apt autoclean

  echo "Fail2Ban and all configurations removed successfully."
}

# TODO: Add ip unban, ssh jail

function showUsage() {
  echo "Usage: $0 [--install | --reinstall | --uninstall]"
  exit 1
}

if [ $# -ne 1 ]; then
  showUsage
fi

case "$1" in
  --install)
    install
    ;;
  --uninstall)
    uninstall
    ;;
  --reinstall)
    uninstall
    install
    ;;
  *)
    showUsage
    ;;
esac