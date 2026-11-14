#!/bin/bash
# End-to-end test for the SOGo image
# Starts the image together with a PostgreSQL database (see compose.yaml), once with its default
# user and once with any other UID, and checks that
#   - the containers become healthy (Apache and sogod are up) without any privileges
#   - all processes run as the expected UID and cron jobs are run
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

process_is_running() {
  in_container "$1" pgrep -x "$2" >/dev/null
}

crontab_was_converted() {
  in_container "$1" cat /var/run/sogo/crontab | diff -u crontab.expected -
}

crontab_is_valid() {
  in_container "$1" supercronic -test /var/run/sogo/crontab >/dev/null 2>&1
}

# Wait up to 10 seconds for the supercronic job writing the UID it runs as
cron_job_ran_as() {
  for i in $(seq 10); do
    [ "$(in_container "$1" cat /tmp/cron-test 2>/dev/null)" = "$2" ] && return 0
    sleep 1
  done
  return 1
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
  check "[$service] sogod is running" process_is_running "$service" sogod
  check "[$service] supercronic is running" process_is_running "$service" supercronic
  check "[$service] crontab with user column was converted" crontab_was_converted "$service"
  check "[$service] converted crontab is valid" crontab_is_valid "$service"
  check "[$service] cron jobs run as UID $uid" cron_job_ran_as "$service" "$uid"
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

if [ $FAILED -ne 0 ]; then
  echo "End-to-end test failed"
  exit 1
fi
echo "End-to-end test passed"
