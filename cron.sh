#!/bin/bash
set -eo pipefail

if [ ! "${DISABLE_CRON}" = "1" ]; then
    echo "Starting supercronic"
    # Load crontab
    if [ ! -f /srv/etc/cron ]; then
        mkdir -p /srv/etc/
        cp -L /template/cron/cron.template /srv/etc/cron
        chmod 0777 /srv/etc/cron
    fi
    # Crontabs of previous versions contain a user column, which supercronic does not support
    /crontab-migrate.sh /srv/etc/cron > /var/run/sogo/crontab
    # Runs in background, its log and the jobs' output go to the container's output
    supercronic /var/run/sogo/crontab &
fi
