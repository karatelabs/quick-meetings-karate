#!/usr/bin/env bash
# reset-sut.sh — put quick-meetings back at the twin's root world: no meetings, and exactly the
# three fixture users the twin declares (ids 1, 2, 3). The API has no reset endpoint, so this is
# the out-of-band reset procedure Twin.live's replays assume.
set -euo pipefail
PGHOST="${PGHOST:-localhost}"
PGPORT="${PGPORT:-5432}"
PGUSER="${PGUSER:-justin}"
PGDATABASE="${PGDATABASE:-quick_meetings}"
SQL="TRUNCATE user_meetings, meetings, users RESTART IDENTITY CASCADE;
     INSERT INTO users (name) VALUES ('alice'), ('bob'), ('charlie');"

if command -v psql > /dev/null 2>&1; then
  PGPASSWORD="${PGPASSWORD:-}" psql -q -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" -c "$SQL" > /dev/null
  PGPASSWORD="${PGPASSWORD:-}" psql -tA -h "$PGHOST" -p "$PGPORT" -U "$PGUSER" -d "$PGDATABASE" \
    -c "SELECT id||':'||name FROM users ORDER BY id;"
else
  docker exec "${PGCONTAINER:-postgres_quick_meetings}" psql -q -U "$PGUSER" -d "$PGDATABASE" -c "$SQL" > /dev/null
  docker exec "${PGCONTAINER:-postgres_quick_meetings}" psql -tA -U "$PGUSER" -d "$PGDATABASE" \
    -c "SELECT id||':'||name FROM users ORDER BY id;"
fi
