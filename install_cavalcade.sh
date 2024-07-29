#!/bin/bash

# Function to print usage
print_usage() {
  echo "Usage: $0 <site_user> <domain.tld>"
  exit 1
}

# Check if correct number of arguments is provided
if [ "$#" -ne 2 ]; then
  print_usage
fi

SITE_USER=$1
DOMAIN=$2
WORDPRESS_ROOT="/home/${SITE_USER}/htdocs/${DOMAIN}"
MU_PLUGINS_DIR="${WORDPRESS_ROOT}/wp-content/mu-plugins"
LOG_DIR="/home/${SITE_USER}/logs/cron"
TASK_MANAGER_SCRIPT="${MU_PLUGINS_DIR}/cavalcade/task_manager.sh"
CRON_OUTPUT="${LOG_DIR}/cavalcadestart.log"

# Ensure running as ubuntu user
if [ "$USER" != "ubuntu" ]; then
  echo "This script must be run as the ubuntu user."
  exit 1
fi

# Create necessary directories and set ownership
sudo -u ${SITE_USER} bash <<EOF
mkdir -p ${MU_PLUGINS_DIR}
mkdir -p ${LOG_DIR}
touch ${LOG_DIR}/cavalcade.log
touch ${LOG_DIR}/cavalcadestart.log
EOF

# Clone repositories and set up files as the site user
sudo -u ${SITE_USER} bash <<EOF
cd ${MU_PLUGINS_DIR}
git clone https://github.com/humanmade/Cavalcade cavalcade

echo "<?php require_once __DIR__ . '/cavalcade/plugin.php';" > ${MU_PLUGINS_DIR}/cavalcade.php

cd cavalcade
git clone https://github.com/humanmade/Cavalcade-Runner runner
EOF

# Get the PATH for the task_manager.sh script
USER_PATH=$(sudo -i -u ${SITE_USER} bash -c 'echo $PATH')

# Create the task_manager.sh script as the site user
sudo -u ${SITE_USER} bash -c "cat > ${TASK_MANAGER_SCRIPT}" <<EOF
#!/usr/bin/env bash

# Set the PATH environment variable
export PATH="${USER_PATH}"

# Set the absolute root for your site
WORDPRESSROOT="${WORDPRESS_ROOT}/"
LOG_DIR="/home/${SITE_USER}/logs/cron"

# Define the Cavalcade path
cd \${WORDPRESSROOT}/wp-content/mu-plugins/cavalcade

# Check if Cavalcade is listed in ps for this specific site
ISCAVALCADEALIVE=\$(ps -aux | grep -v grep | grep "mu-plugins/cavalcade/runner/bin/cavalcade \${WORDPRESSROOT}")

# Function to log with timestamp
log_with_timestamp() {
    while IFS= read -r line; do
        echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$line" >> \${LOG_DIR}/cavalcade.log
    done
}

# Restart Cavalcade if it isn't listed, otherwise chill
if [[ -z "\${ISCAVALCADEALIVE}" ]]; then
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - Cavalcade is not running, starting now..." >> \${LOG_DIR}/cavalcade.log
    nohup /usr/bin/php -d error_reporting="E_ALL & ~E_DEPRECATED & ~E_NOTICE" \${WORDPRESSROOT}wp-content/mu-plugins/cavalcade/runner/bin/cavalcade \${WORDPRESSROOT} 2>&1 | log_with_timestamp &
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - All is well. Cavalcade is running for \${WORDPRESSROOT}." >> \${LOG_DIR}/cavalcade.log
fi
EOF

# Make the task_manager.sh script executable
sudo chmod +x ${TASK_MANAGER_SCRIPT}

# Output the cron job command
echo "Add the following cron job in CloudPanel:"
echo "/bin/bash ${TASK_MANAGER_SCRIPT} > ${CRON_OUTPUT} 2>&1"
