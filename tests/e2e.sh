#!/bin/bash
# End-to-end test for the SOGo image
# Starts the image together with a PostgreSQL database (see compose.yaml) and checks that
#   - the container becomes healthy (Apache and sogod are up)
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
    compose logs --no-log-prefix --tail 100 sogo || true
  fi
  compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  rm -f "$COOKIES"
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
echo "PASS: container is healthy"

URL="http://$(compose port sogo 80)"

check "sogod is running" sh -c "docker compose --project-name $PROJECT exec -T sogo pgrep -x sogod >/dev/null"
check "static content is served" \
  curl -fsS -o /dev/null "$URL/SOGo.woa/WebServerResources/js/Common.js"
check "login page is served" \
  sh -c "curl -fsSL '$URL/SOGo/' | grep -q 'SOGo'"
check "user can log in" \
  curl -fsS -o /dev/null -c "$COOKIES" -H 'Content-Type: application/json' \
    -d '{"userName":"test","password":"test"}' "$URL/SOGo/connect"
check "calendar view is served" \
  curl -fsS -o /dev/null -b "$COOKIES" "$URL/SOGo/so/test/Calendar/view"
check "personal calendar was created in the database" \
  sh -c "docker compose --project-name $PROJECT exec -T db psql -U sogo -tAc 'SELECT c_path FROM sogo_folder_info' | grep -qx '/Users/test/Calendar/personal'"

if [ $FAILED -ne 0 ]; then
  echo "End-to-end test failed"
  exit 1
fi
echo "End-to-end test passed"
