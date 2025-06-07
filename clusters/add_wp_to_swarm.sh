#!/bin/bash
set -e

STACK_NAME=$1  # e.g. mywordpress

if [[ -z "$STACK_NAME" ]]; then
  echo "Usage: $0 <stack_name>"
  exit 1
fi

# Generate MySQL credentials
MYSQL_ROOT_PASSWORD=$(openssl rand -hex 12)
MYSQL_USER="wpuser_$(openssl rand -hex 4)"
MYSQL_PASSWORD=$(openssl rand -hex 12)
MYSQL_DATABASE="${STACK_NAME}_db"
NETWORK_NAME="${STACK_NAME}_net"

# Generate WordPress secret keys
generate_key() {
  openssl rand -base64 48
}

AUTH_KEY=$(generate_key)
SECURE_AUTH_KEY=$(generate_key)
LOGGED_IN_KEY=$(generate_key)
NONCE_KEY=$(generate_key)
AUTH_SALT=$(generate_key)
SECURE_AUTH_SALT=$(generate_key)
LOGGED_IN_SALT=$(generate_key)
NONCE_SALT=$(generate_key)

# Create overlay network if it doesn't exist
if ! docker network ls --filter name=^"${NETWORK_NAME}"$ --format '{{.Name}}' | grep -wq "${NETWORK_NAME}"; then
  echo "Creating overlay network: $NETWORK_NAME"
  docker network create -d overlay "$NETWORK_NAME"
else
  echo "Network $NETWORK_NAME already exists"
fi

# Create shared bind mount folders (local setup; Syncthing will sync between nodes)
UPLOADS_DIR="/var/lib/docker/volumes/${STACK_NAME}_wp_data/_data"
DB_DIR="/var/lib/docker/volumes/${STACK_NAME}_db_data/_data"

mkdir -p "$UPLOADS_DIR" "$DB_DIR"
chown -R 33:33 "$UPLOADS_DIR"  # www-data UID:GID for WordPress

# Generate wp-config.php
WP_CONFIG_GENERATED=$(mktemp)

cat > "$WP_CONFIG_GENERATED" <<EOF
<?php
// Auto-generated wp-config.php

define('DB_NAME', '${MYSQL_DATABASE}');
define('DB_USER', '${MYSQL_USER}');
define('DB_PASSWORD', '${MYSQL_PASSWORD}');
define('DB_HOST', 'db:3306');
define('DB_CHARSET', 'utf8');
define('DB_COLLATE', '');

// Authentication Unique Keys and Salts.
define('AUTH_KEY',         '${AUTH_KEY}');
define('SECURE_AUTH_KEY',  '${SECURE_AUTH_KEY}');
define('LOGGED_IN_KEY',    '${LOGGED_IN_KEY}');
define('NONCE_KEY',        '${NONCE_KEY}');
define('AUTH_SALT',        '${AUTH_SALT}');
define('SECURE_AUTH_SALT', '${SECURE_AUTH_SALT}');
define('LOGGED_IN_SALT',   '${LOGGED_IN_SALT}');
define('NONCE_SALT',       '${NONCE_SALT}');

\$table_prefix = 'wp_';

if (!defined('ABSPATH')) {
    define('ABSPATH', __DIR__ . '/');
}

require_once ABSPATH . 'wp-settings.php';
EOF

echo "Creating Docker config for wp-config.php..."
docker config rm "${STACK_NAME}_wp_config" 2>/dev/null || true
docker config create "${STACK_NAME}_wp_config" "$WP_CONFIG_GENERATED"
rm "$WP_CONFIG_GENERATED"

# Create docker-compose temp file
COMPOSE_FILE=$(mktemp)

cat > "$COMPOSE_FILE" <<EOF
version: '3.8'

services:
  db:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: $MYSQL_ROOT_PASSWORD
      MYSQL_DATABASE: $MYSQL_DATABASE
      MYSQL_USER: $MYSQL_USER
      MYSQL_PASSWORD: $MYSQL_PASSWORD
    volumes:
      - /var/lib/docker/volumes/${STACK_NAME}_db_data/_data:/var/lib/mysql
    networks:
      - $NETWORK_NAME
    deploy:
      placement:
        constraints:
          - node.role == worker

  wordpress:
    image: wordpress:latest
    depends_on:
      - db
    environment:
      WORDPRESS_DB_HOST: db:3306
      WORDPRESS_DB_USER: $MYSQL_USER
      WORDPRESS_DB_PASSWORD: $MYSQL_PASSWORD
      WORDPRESS_DB_NAME: $MYSQL_DATABASE
    configs:
      - source: ${STACK_NAME}_wp_config
        target: /var/www/html/wp-config.php
        mode: 0444
    volumes:
      - /var/lib/docker/volumes/${STACK_NAME}_wp_data/_data:/var/www/html/wp-content/uploads
    ports:
      - "8080:80"
    networks:
      - $NETWORK_NAME
    deploy:
      placement:
        constraints:
          - node.role == worker

configs:
  ${STACK_NAME}_wp_config:
    external: true

networks:
  $NETWORK_NAME:
    external: true
EOF

echo "Deploying stack '$STACK_NAME'..."
docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"
rm "$COMPOSE_FILE"

echo
echo "✅ WordPress stack '$STACK_NAME' deployed successfully!"
echo "🌐 Access it at: http://<your-node-ip>:8080"
echo "🔄 Make sure Syncthing is syncing:"
echo "  - $UPLOADS_DIR across all nodes"
