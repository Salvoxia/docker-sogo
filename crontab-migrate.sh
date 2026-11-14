#!/bin/bash
# Converts a crontab to the format supercronic expects and prints it to stdout.
#
# Previous versions of this image used cron with a crontab in the /etc/cron.d format,
# which contains a user column after the schedule:
#   * * * * *  sogo  /usr/local/sbin/sogo-tool expire-sessions 60
# supercronic runs all jobs as the container's user and expects no user column:
#   * * * * *  /usr/local/sbin/sogo-tool expire-sessions 60
#
# The user column is removed from jobs for the container's user. Jobs for any other user
# cannot be run and are commented out. All other lines are kept as they are.
# Notices about converted or disabled jobs are printed to stderr.
#
# Usage: crontab-migrate.sh <crontab>
set -eo pipefail

CRONTAB=${1:?Usage: $0 <crontab>}
CURRENT_USER=$(id -un)
# "@daily user command"
SPECIAL_SCHEDULE_REGEX='^([[:space:]]*@[[:alpha:]]+[[:space:]]+)([^[:space:]]+)[[:space:]]+(.*)$'
# "* * * * * user command", the first five fields are the schedule
SCHEDULE_REGEX='^([[:space:]]*([^[:space:]]+[[:space:]]+){5})([^[:space:]]+)[[:space:]]+(.*)$'
converted=0

while IFS= read -r line || [ -n "$line" ]; do
  user=""
  # Comments, empty lines and environment variables are kept
  if [[ $line =~ ^[[:space:]]*(#|$) ]] || [[ $line =~ ^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*[[:space:]]*= ]]; then
    :
  elif [[ $line =~ $SPECIAL_SCHEDULE_REGEX ]]; then
    schedule=${BASH_REMATCH[1]} user=${BASH_REMATCH[2]} command=${BASH_REMATCH[3]}
  elif [[ $line =~ $SCHEDULE_REGEX ]]; then
    schedule=${BASH_REMATCH[1]} user=${BASH_REMATCH[3]} command=${BASH_REMATCH[4]}
  fi

  # The field after the schedule is only a user column if it names an existing user,
  # otherwise it is the job's command
  if [ -z "$user" ] || ! getent passwd "$user" >/dev/null; then
    printf '%s\n' "$line"
  elif [ "$user" = "$CURRENT_USER" ]; then
    printf '%s%s\n' "$schedule" "$command"
    converted=1
  else
    printf '# Disabled, jobs can only run as user %s: %s\n' "$CURRENT_USER" "$line"
    echo "WARNING: $CRONTAB: disabled job for user $user, jobs can only run as user $CURRENT_USER: $line" >&2
  fi
done < "$CRONTAB"

if [ $converted -eq 1 ]; then
  echo "NOTICE: $CRONTAB contains jobs with a user column, which is deprecated. They were converted automatically, remove the user column to get rid of this notice." >&2
fi
