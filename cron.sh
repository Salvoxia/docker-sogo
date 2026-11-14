#!/bin/bash
set -eo pipefail

# Cron jobs are configured with CRON_* environment variables:
#   unset, empty or "0": disabled ("0" also disables CRON_TMPWATCH, which is enabled when unset)
#   "1": enabled with the job's default schedule
#   anything else: enabled with this value as schedule, e.g. "*/10 * * * *"
CRONTAB=/var/run/sogo/crontab

# Adds a job to the crontab if it is enabled by its environment variable
# Usage: add_job <variable> <default schedule> <command> [<value if unset>]
add_job() {
  local variable=$1 default_schedule=$2 command=$3 unset_value=${4:-0}
  local value=${!variable-$unset_value} schedule test_output
  case "$value" in
    ""|0) return ;;
    1) schedule=$default_schedule ;;
    *) schedule=$value ;;
  esac
  echo "$schedule $command" > "$CRONTAB.test"
  if ! test_output=$(supercronic -test "$CRONTAB.test" 2>&1); then
    echo "ERROR: $variable: invalid schedule \"$value\""
    echo "$test_output"
    exit 1
  fi
  echo "$schedule $command" >> "$CRONTAB"
  echo "Cron job $variable: $schedule $command"
}

if [ ! "${DISABLE_CRON}" = "1" ]; then
    # Crontab of previous versions, which is no longer used
    if [ -f /srv/etc/cron ]; then
        /cron-legacy-check.sh /srv/etc/cron
    fi

    echo "# Generated from CRON_* environment variables during startup" > "$CRONTAB"
    add_job CRON_UPDATE_AUTOREPLY "*/5 * * * *" "/usr/local/sbin/sogo-tool update-autoreply -p /srv/etc/sieve.creds"
    if grep -q update-autoreply "$CRONTAB" && [ ! -f /srv/etc/sieve.creds ]; then
        echo "WARNING: CRON_UPDATE_AUTOREPLY is enabled, but /srv/etc/sieve.creds with the Sieve admin credentials (username:password) is missing"
    fi
    add_job CRON_EXPIRE_SESSIONS "* * * * *" "/usr/local/sbin/sogo-tool expire-sessions 60 > /dev/null 2>&1"
    # SMTP credentials are optional
    EALARMS_CREDENTIALS=""
    [ -f /srv/etc/smtp.creds ] && EALARMS_CREDENTIALS=" -p /srv/etc/smtp.creds"
    add_job CRON_EALARMS_NOTIFY "* * * * *" "/usr/local/sbin/sogo-ealarms-notify$EALARMS_CREDENTIALS > /dev/null 2>&1"
    add_job CRON_BACKUP "30 0 * * *" "/srv/sogo-backup.sh"
    add_job CRON_CLEANUP "0 1 * * 0" "/usr/local/sbin/sogo-tool cleanup 30 ALL"
    add_job CRON_CLEAN_OPENID_SESSIONS "0 * * * *" "/usr/local/sbin/sogo-tool clean-openid-sessions"
    add_job CRON_TMPWATCH "0 3 * * *" "/sogo-tmpwatch.sh" 1
    rm -f "$CRONTAB.test"

    if grep -qv '^#' "$CRONTAB"; then
        echo "Starting supercronic"
        # Runs in background, its log and the jobs' output go to the container's output
        supercronic "$CRONTAB" &
    else
        echo "No cron jobs enabled, not starting supercronic"
    fi
fi
