#!/bin/bash
set -eo pipefail
# Copy Config
# Create default config if non provided
if [ ! -f /srv/etc/apache-SOGo.conf ]; then
  mkdir -p /srv/etc/
  cp -L /template/apache2/SOGo.conf.template /srv/etc/apache-SOGo.conf
  chmod 0777 /srv/etc/apache-SOGo.conf
fi
cp -L /srv/etc/apache-SOGo.conf /etc/apache2/conf-enabled/SOGo.conf


# Run apache2 in background
exec /usr/sbin/apache2ctl start