#!/bin/bash
# End-to-end test for the SOGo image
# Starts the image together with a PostgreSQL database (see compose.yaml), once with its default
# user and once with any other UID, and checks that
#   - the containers become healthy (Apache and sogod are up) without any privileges
#   - all processes run as the expected UID and cron jobs from CRON_* variables are run
#   - Apache serves static content
#   - a user can log in and SOGo creates the user's calendar in the database
#
# Usage: tests/e2e.sh <image>
set -eo pipefail

export SOGO_IMAGE=${1:?Usage: $0 <image>}
cd "$(dirname "$0")"
PROJECT=sogo-e2e-$$
COOKIES=$(mktemp)
FAILED=0

compose() {
  docker compose --project-name $PROJECT --file compose.yaml "$@"
}

cleanup() {
  rc=$?
  if [ $rc -ne 0 ] || [ $FAILED -ne 0 ]; then
    echo "----- container output -----"
    compose logs --tail 100 sogo sogo-any-uid || true
  fi
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -f "$COOKIES" "$COOKIES".*
}
trap cleanup EXIT

# Run a check, print the result and remember failures
check() {
  local name=$1; shift
  if "$@"; then
    echo "PASS: $name"
  else
    echo "FAIL: $name"
    FAILED=1
  fi
}

echo "Starting $SOGO_IMAGE and PostgreSQL"
# --wait fails if a container exits or becomes unhealthy
if ! compose up --detach --wait --wait-timeout 180 --quiet-pull; then
  echo "Containers did not become healthy"
  exit 1
fi
echo "PASS: containers are healthy"

# Run a command in a container of the test environment
in_container() {
  local service=$1; shift
  compose exec -T "$service" "$@"
}

all_processes_run_as() {
  local uids
  uids=$(in_container "$1" ps -eo uid=) || return 1
  ! grep -qvx " *$2" <<<"$uids"
}

# Everything outside these locations must be read-only for the container's user
WRITABLE_LOCATIONS="/tmp /var/tmp /run/lock /srv /etc/sogo /run/sogo /run/apache2 /var/log/apache2 /var/log/sogo /var/spool/sogo /etc/apache2/conf-enabled/SOGo.conf"

# Prints all paths matching the find expression, skipping the kernel's file systems
find_in_container() {
  local service=$1; shift
  in_container "$service" sh -c 'find / \( -path /proc -o -path /sys -o -path /dev \) -prune -o "$@" -print 2>/dev/null; true' find "$@"
}

only_expected_locations_are_writable() {
  local pattern unexpected
  pattern="^($(tr ' ' '|' <<<"$WRITABLE_LOCATIONS"))(/|$)"
  # Symlinks are skipped, their targets are checked themselves
  unexpected=$(find_in_container "$1" -writable ! -type l | grep -vE "$pattern") || true
  [ -z "$unexpected" ] || { echo "Unexpected writable paths:"; echo "$unexpected"; return 1; }
}

nothing_is_world_writable() {
  local found
  # Sticky directories like /tmp are writable for everyone by design
  found=$(find_in_container "$1" -perm -o+w ! -type l ! \( -type d -perm -1000 \))
  [ -z "$found" ] || { echo "World-writable paths:"; echo "$found"; return 1; }
}

process_is_running() {
  in_container "$1" pgrep -x "$2" >/dev/null
}

crontab_was_generated() {
  in_container "$1" cat /var/run/sogo/crontab | diff -u crontab.expected -
}

crontab_is_valid() {
  in_container "$1" supercronic -test /var/run/sogo/crontab >/dev/null 2>&1
}

# The spool cleanup job runs every 2 seconds and removes files of the container's UID,
# which have not been accessed for more than 23 days. Wait up to 10 seconds for it.
cron_job_cleaned_spool() {
  in_container "$1" sh -c 'mkdir -p /var/spool/sogo/e2e && touch -d "30 days ago" /var/spool/sogo/e2e/draft' || return 1
  for i in $(seq 10); do
    in_container "$1" test -e /var/spool/sogo/e2e/draft || return 0
    sleep 1
  done
  return 1
}

legacy_crontab_warnings() {
  local log
  log=$(compose logs --no-log-prefix "$1") || return 1
  # Only jobs which are not enabled with CRON_* variables cause a warning, see legacy-cron
  grep -qF 'set CRON_EALARMS_NOTIFY="*/5 * * * *" to run it' <<<"$log" &&
    grep -qF 'custom job is not run anymore' <<<"$log" &&
    ! grep -qE 'set CRON_(EXPIRE_SESSIONS|BACKUP|CLEANUP)=' <<<"$log"
}

invalid_schedule_is_rejected() {
  local output
  output=$(docker run --rm -e CRON_BACKUP="every day" "$SOGO_IMAGE" 2>&1) && return 1
  grep -qF 'ERROR: CRON_BACKUP: invalid schedule "every day"' <<<"$output"
}

login_page_is_served() {
  curl -fsSL "$1/SOGo/" | grep -q 'SOGo'
}

calendar_was_created() {
  in_container db psql -U sogo -tAc 'SELECT c_path FROM sogo_folder_info' | grep -qx '/Users/test/Calendar/personal'
}

# Run all checks against a SOGo container, which is expected to run with the given UID
check_sogo() {
  local service=$1 uid=$2
  local url="http://$(compose port "$service" 8080)"
  local cookies="$COOKIES.$service"
  echo "Checking $service (UID $uid)"
  check "[$service] all processes run as UID $uid" all_processes_run_as "$service" "$uid"
  check "[$service] only the expected locations are writable" only_expected_locations_are_writable "$service"
  check "[$service] nothing is world-writable" nothing_is_world_writable "$service"
  check "[$service] sogod is running" process_is_running "$service" sogod
  check "[$service] supercronic is running" process_is_running "$service" supercronic
  check "[$service] crontab was generated from CRON_* variables" crontab_was_generated "$service"
  check "[$service] generated crontab is valid" crontab_is_valid "$service"
  check "[$service] cron job cleaned up the spool directory as UID $uid" cron_job_cleaned_spool "$service"
  check "[$service] crontab of previous versions causes warnings" legacy_crontab_warnings "$service"
  check "[$service] static content is served" \
    curl -fsS -o /dev/null "$url/SOGo.woa/WebServerResources/js/Common.js"
  check "[$service] login page is served" login_page_is_served "$url"
  check "[$service] user can log in" \
    curl -fsS -o /dev/null -c "$cookies" -H 'Content-Type: application/json' \
      -d '{"userName":"test","password":"test"}' "$url/SOGo/connect"
  check "[$service] calendar view is served" \
    curl -fsS -o /dev/null -b "$cookies" "$url/SOGo/so/test/Calendar/view"
}

# The image's default user
check_sogo sogo 999
# Any UID, which does not exist in the image
check_sogo sogo-any-uid 12345
check "personal calendar was created in the database" calendar_was_created
check "invalid cron schedule is rejected" invalid_schedule_is_rejected

if [ $FAILED -ne 0 ]; then
  echo "End-to-end test failed"
  exit 1
fi
echo "End-to-end test passed"
