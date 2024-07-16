# Start Cron
/cron.sh
# Start Memcached
/memcached.sh
# Start Apache2
rm -f /var/run/apache2/apache2.pid
/apache2.sh
# Start SOGo Daemon
/sogod.sh