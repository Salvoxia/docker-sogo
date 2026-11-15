#!/bin/bash
set -eo pipefail

if [ ! "${DISABLE_MEMCACHED}" = "1" ]; then
    echo "Starting memcached"
    # Started directly in background, the init script requires root privileges
    memcached -d -l 127.0.0.1 -p 11211 -m 64 -P /var/run/sogo/memcached.pid
fi
