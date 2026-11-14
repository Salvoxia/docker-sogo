# Missing files are created from templates. The container runs as user sogo, so this fails
# if their directory is not writable for it, e.g. in volumes created by previous versions
CREATED_FILES="/srv/etc/sogo.conf /srv/etc/apache-SOGo.conf /srv/sogo-backup.sh /srv/lib/sogo"
[ "${DISABLE_CRON}" = "1" ] || CREATED_FILES="$CREATED_FILES /srv/etc/cron"
for path in $CREATED_FILES; do
  [ -e "$path" ] && continue
  dir=$(dirname "$path")
  while [ ! -e "$dir" ]; do dir=$(dirname "$dir"); done
  if [ ! -w "$dir" ]; then
    echo "WARNING: $path is missing and cannot be created, $dir is not writable for user $(id -un) ($(id -u):$(id -g)). Refer to the \"Permissions\" section of the README."
  fi
done
# SOGo's home directory contains backups and user defaults
if [ -d /srv/lib/sogo ] && [ ! -w /srv/lib/sogo ]; then
  echo "WARNING: /srv/lib/sogo is not writable for user $(id -un) ($(id -u):$(id -g)), backups and user defaults cannot be saved. Refer to the \"Permissions\" section of the README."
fi
# Start Cron
/cron.sh
# Start Memcached
/memcached.sh
# Start Apache2
rm -f /var/run/apache2/apache2.pid
/apache2.sh
# Start SOGo Daemon
/sogod.sh
