#!/bin/bash
set -e

STACK_NAME=$1  # e.g. mywordpress

if [[ -z "$STACK_NAME" ]]; then
  echo "Usage: $0 <stack_name>"
  exit 1
fi

# Generate random MySQL credentials
MYSQL_ROOT_PASSWORD=$(openssl rand -hex 12)
MYSQL_USER="wpuser_$(openssl rand -hex 4)"
MYSQL_PASSWORD=$(openssl rand -hex 12)
MYSQL_DATABASE="${STACK_NAME}_db"
NETWORK_NAME="${STACK_NAME}_net"

# Generate secure keys for wp-config.php
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

# Generate wp-config.php dynamically
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

# Create temporary docker-compose file
COMPOSE_FILE=$(mktemp)

cat > "$COMPOSE_FILE" <<EOF
version: '3.8'

services:
  db:
    image: mysql:8.0
    environment:
      MYSQL_ROOT_PASSWORD: ...
    volumes:
      - /var/lib/docker/volumes/${STACK_NAME}_db_data/_data:/var/lib/mysql
    networks:
      - ${STACK_NAME}_net

  wordpress:
    image: wordpress:latest
    volumes:
      - /var/lib/docker/volumes/${STACK_NAME}_wp_data/_data:/var/www/html/wp-content/uploads
    configs:
      - source: ${STACK_NAME}_wp_config
        target: /var/www/html/wp-config.php
        mode: 0444
    networks:
      - ${STACK_NAME}_net

configs:
  ${STACK_NAME}_wp_config:
    external: true

networks:
  ${STACK_NAME}_net:
    external: true
EOF

echo "Deploying stack '$STACK_NAME'..."
docker stack deploy -c "$COMPOSE_FILE" "$STACK_NAME"

rm "$COMPOSE_FILE"

echo "WordPress stack '$STACK_NAME' deployed successfully!"
echo "Access it at http://<your-swarm-node-ip>:8080"
