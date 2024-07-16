# Load crontab
if [ ! "${DISABLE_MEMCACHED}" = "1" ]; then
    echo "Starting memcached"
    service memcached start
fi