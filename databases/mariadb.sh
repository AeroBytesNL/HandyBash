#!/bin/bash

set -e

function installMariaDB() {
  echo "Updating package lists..."
  sudo apt-get update

  echo "Installing MariaDB server and client..."
  sudo apt-get install -y mariadb-server mariadb-client

  echo "Enabling and starting MariaDB service..."
  sudo systemctl enable mariadb
  sudo systemctl start mariadb

  echo "MariaDB installed successfully."
  echo "Run 'sudo mysql_secure_installation' to secure your setup."
}


function uninstallMariaDB() {
  echo "Stopping MariaDB services..."
  sudo systemctl stop mariadb || true

  echo "Uninstalling MariaDB packages..."
  sudo apt-get remove --purge -y mariadb-server mariadb-client mariadb-common galera-4

  echo "Removing MariaDB data directories and config files..."
  sudo rm -rf /etc/mysql /var/lib/mysql /var/log/mysql /var/log/mysql.* /var/run/mysqld

  echo "Removing MariaDB residual packages and dependencies..."
  sudo apt-get autoremove -y
  sudo apt-get autoclean

  echo "MariaDB and all configurations removed successfully."
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
    installMariaDB
    ;;
  --uninstall)
    uninstallMariaDB
    ;;
  --reinstall)
    uninstallMariaDB
    installMariaDB
    ;;
  *)
    showUsage
    ;;
esac