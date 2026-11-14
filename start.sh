# The container can run with any UID, which might not have a user name
USER_NAME=$(id -un 2>/dev/null) || USER_NAME=$(id -u)
USER_INFO="user $USER_NAME ($(id -u):$(id -g))"
# Writable locations in the image belong to user sogo and group root, any other UID needs GID 0
if [ "$(id -u)" != "999" ]; then
  case " $(id -G) " in
    *" 0 "*) ;;
    *)
      echo "ERROR: The container runs as $USER_INFO, which is not a member of group root (GID 0). When running with another UID than 999, use GID 0, e.g. --user $(id -u):0. Refer to the \"Permissions\" section of the README."
      exit 1
      ;;
  esac
fi

# Missing files are created from templates. The container runs without root privileges, so this
# fails if their directory is not writable for it, e.g. in volumes created by previous versions
CREATED_FILES="/srv/etc/sogo.conf /srv/etc/apache-SOGo.conf /srv/sogo-backup.sh /srv/lib/sogo"
[ "${DISABLE_CRON}" = "1" ] || CREATED_FILES="$CREATED_FILES /srv/etc/cron"
for path in $CREATED_FILES; do
  [ -e "$path" ] && continue
  dir=$(dirname "$path")
  while [ ! -e "$dir" ]; do dir=$(dirname "$dir"); done
  if [ ! -w "$dir" ]; then
    echo "WARNING: $path is missing and cannot be created, $dir is not writable for $USER_INFO. Refer to the \"Permissions\" section of the README."
  fi
done
# SOGo's home directory contains backups and user defaults
if [ -d /srv/lib/sogo ] && [ ! -w /srv/lib/sogo ]; then
  echo "WARNING: /srv/lib/sogo is not writable for $USER_INFO, backups and user defaults cannot be saved. Refer to the \"Permissions\" section of the README."
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
