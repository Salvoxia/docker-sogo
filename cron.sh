# Load crontab

if [ ! "${DISABLE_CRON}" = "1" ]; then
    echo "Starting cron"
    # Load crontab
    if [ ! -f /srv/etc/cron ]; then
        mkdir -p /srv/etc/
        cp -L /template/cron/cron.template /srv/etc/cron
        chmod 0777 /srv/etc/cron
    fi
    cp -L /srv/etc/cron /etc/cron.d/sogo
    service cron start
fi