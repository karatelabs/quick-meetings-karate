#!/usr/bin/env bash
# app.sh — build and run quick-meetings (the SUT at the repo root) on :9981. [up|down|status]
set -euo pipefail
cd "$(dirname "$0")/.."
SUT="$(pwd)"
PORT="${QM_PORT:-9981}"
LOG="$SUT/karate/target/app.log"

is_up() { curl -sf -o /dev/null -X POST "http://localhost:$PORT/user?name=probe" 2>/dev/null; }

up() {
  if is_up; then echo "already up — :$PORT"; return 0; fi
  mkdir -p "$SUT/karate/target"
  ( cd "$SUT" && nohup mvn -q spring-boot:run > "$LOG" 2>&1 & )
  for _ in $(seq 1 120); do
    if is_up; then echo "up — :$PORT"; return 0; fi
    sleep 2
  done
  echo "ERROR: did not come up" >&2; tail -30 "$LOG" >&2; exit 1
}

down() {
  pkill -f 'spring-boot:run' 2>/dev/null || true
  pkill -f 'quickmeetings' 2>/dev/null || true
  sleep 2
  echo "stopped."
}

case "${1:-up}" in
  up|start) up ;;
  down|stop) down ;;
  status) is_up && echo up || echo down ;;
  *) echo "usage: ./app.sh [up|down|status]" >&2; exit 2 ;;
esac
