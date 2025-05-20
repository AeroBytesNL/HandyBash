#!/bin/bash
HOST=$1
PORT=$2

if [ -z "$HOST" ] || [ -z "$PORT" ]; then
  echo "Usage: $0 <host> <port>"
  exit 1
fi

echo "Testing $HOST:$PORT..."
timeout 3 bash -c "cat < /dev/null > /dev/tcp/$HOST/$PORT" && echo "Open" || echo "Closed"