#!/bin/bash
set -eo pipefail

#Solve libssl bug for Mail View
LIBSSL_LOCATION=$(find /lib /usr/lib /usr/local/lib -type f -name "libssl.so.*" -print -quit)
export LD_PRELOAD=$LIBSSL_LOCATION

# Copy back administrator's configuration
# Create default config if non provided
if [ ! -f /srv/etc/sogo.conf ]; then
  mkdir -p /srv/etc/
  cp -L /template/sogo/sogo.conf.template /srv/etc/sogo.conf#
  chmod 0777 /srv/etc/sogo.conf
fi
cp -L /srv/etc/sogo.conf /etc/sogo/sogo.conf
chown -R sogo:sogo /etc/sogo/sogo.conf

# Make backup script available
if [ ! -f /srv/sogo-backup.sh ]; then
  mkdir -p /srv
  cp -L /template/sogo/sogo-backup.sh /srv/sogo-backup.sh
  chmod 0777 /srv/sogo-backup.sh
fi

# Create SOGo home directory if missing
mkdir -p /srv/lib/sogo
chown -R sogo:sogo /srv/lib/sogo

# Load crontab
if [ ! -f /srv/etc/cron ]; then
  mkdir -p /srv/etc/
  cp -L /template/cron/cron.template /srv/etc/cron
  chmod 0777 /srv/etc/cron
fi
cp -L /srv/etc/cron /etc/cron.d/sogo

# Run SOGo in background
LD_PRELOAD=$LD_PRELOAD exec su sogo -c '/usr/local/sbin/sogod -WOUseWatchDog $USEWATCHDOG -WOPort "127.0.0.1:20000" -WOPidFile /var/run/sogo/sogo.pid'