#!/bin/bash
# Previous versions of this image read cron jobs from /srv/etc/cron, they are now configured
# with CRON_* environment variables instead (see cron.sh).
# Prints a warning for each job in the file, which is not run anymore, naming the environment
# variable to set instead.
#
# Usage: cron-legacy-check.sh <crontab>
set -eo pipefail

CRONTAB=${1:?Usage: $0 <crontab>}
# "@daily [user] command"
SPECIAL_SCHEDULE_REGEX='^[[:space:]]*(@[[:alpha:]]+)[[:space:]]+(.*)$'
# "* * * * * [user] command", the first five fields are the schedule
SCHEDULE_REGEX='^[[:space:]]*(([^[:space:]]+[[:space:]]+){4}[^[:space:]]+)[[:space:]]+(.*)$'

echo "WARNING: $CRONTAB is no longer used, cron jobs are configured with CRON_* environment variables. Refer to the \"Cron Jobs\" section of the README."

while IFS= read -r line || [ -n "$line" ]; do
  # Comments, empty lines and environment variables
  if [[ $line =~ ^[[:space:]]*(#|$) ]] || [[ $line =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*= ]]; then
    continue
  elif [[ $line =~ $SPECIAL_SCHEDULE_REGEX ]]; then
    schedule=${BASH_REMATCH[1]} command=${BASH_REMATCH[2]}
  elif [[ $line =~ $SCHEDULE_REGEX ]]; then
    schedule=${BASH_REMATCH[1]} command=${BASH_REMATCH[3]}
  else
    echo "WARNING: $CRONTAB: ignoring invalid line: $line"
    continue
  fi

  case "$command" in
    *update-autoreply*) variable=CRON_UPDATE_AUTOREPLY ;;
    *expire-sessions*) variable=CRON_EXPIRE_SESSIONS ;;
    *ealarms-notify*) variable=CRON_EALARMS_NOTIFY ;;
    *sogo-backup.sh*) variable=CRON_BACKUP ;;
    *clean-openid-sessions*) variable=CRON_CLEAN_OPENID_SESSIONS ;;
    *"sogo-tool cleanup"*) variable=CRON_CLEANUP ;;
    *tmpwatch*) variable=CRON_TMPWATCH ;;
    *) variable="" ;;
  esac

  if [ -z "$variable" ]; then
    echo "WARNING: $CRONTAB: custom job is not run anymore, only the jobs configurable with CRON_* environment variables are supported: $line"
  elif [ -z "${!variable}" ] || [ "${!variable}" = "0" ]; then
    echo "WARNING: $CRONTAB: job is not run anymore, set $variable=\"$schedule\" to run it: $line"
  fi
done < "$CRONTAB"
