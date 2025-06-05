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

function banIp() {
  local JAIL="$1"
  local IP="$2"

  if [[ -z "$JAIL" || -z "$IP" ]]; then
    echo "Usage: $0 --ban <jail> <ip>"
    exit 1
  fi

  echo "Banning IP $IP in jail $JAIL..."
  sudo fail2ban-client set "$JAIL" banip "$IP"
}

function unbanIp() {
  local JAIL="$1"
  local IP="$2"

  if [[ -z "$JAIL" || -z "$IP" ]]; then
    echo "Usage: $0 --unban <jail> <ip>"
    exit 1
  fi

  echo "Unbanning IP $IP in jail $JAIL..."
  sudo fail2ban-client set "$JAIL" unbanip "$IP"
}

function checkIp() {
  local JAIL="$1"
  local IP="$2"

  if [[ -z "$JAIL" || -z "$IP" ]]; then
    echo "Usage: $0 --check <jail> <ip>"
    exit 1
  fi

  echo "Checking if IP $IP is banned in jail $JAIL..."
  if sudo fail2ban-client status "$JAIL" | grep -q "$IP"; then
    echo "IP $IP is currently banned in $JAIL."
  else
    echo "IP $IP is not banned in $JAIL."
  fi
}

function listJails() {
  echo "Retrieving active Fail2Ban jails..."
  local jails
  jails=$(sudo fail2ban-client status | grep 'Jail list:' | cut -d: -f2 | tr -d ' ')

  if [[ -z "$jails" ]]; then
    echo "No jails found."
  else
    echo "Active jails:"
    IFS=',' read -ra jail_array <<< "$jails"
    for jail in "${jail_array[@]}"; do
      echo " - $jail"
    done
  fi
}

function showUsage() {
  echo "Usage:"
  echo "$0 --install"
  echo "$0 --uninstall"
  echo "$0 --reinstall"
  echo "$0 --ban <jail> <ip>"
  echo "$0 --unban <jail> <ip>"
  echo "$0 --check-ip <jail> <ip>"
  echo "$0 --get-jails"
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
  --ban)
    banIp "$2" "$3"
    ;;
  --unban)
    unbanIp "$2" "$3"
    ;;
  --check)
    checkIp "$2" "$3"
    ;;
  *)
    showUsage
    ;;
esac