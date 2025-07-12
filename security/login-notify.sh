#!/bin/bash

# Sends a notification on SSH login
# Currently supports Discord only

# Add the following rule to /etc/pam.d/sshd:
# auth optional pam_exec.se seteuid /usr/local/bin/login-notify.sh

# Dont forget to make the script executable: sudo chmod +x /usr/local/bin/login-notify.sh

WEBHOOK_URL=""
HOSTNAME=$(hostname)
USER=$(whoami)
IP=$(echo $PAM_RHOST)

curl -H "Content-Type: application/json" \
  -X POST \
  -d "{
    \"username\": \"LoginNotifier\",
    \"content\": \"🔐 Inlog (poging) op \`$HOSTNAME\` door gebruiker \`$PAM_USER\` vanaf IP \`$IP\`\"
  }" \
  $WEBHOOK_URL