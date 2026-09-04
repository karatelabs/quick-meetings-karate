#!/usr/bin/env bash
# serve.sh — anchor a karate console at this folder. ./serve.sh [up|down|status|restart]
set -euo pipefail
cd "$(dirname "$0")"
HERE="$(pwd)"
PORT="${KARATE_SERVE_PORT:-8099}"
PIDFILE="$HERE/.serve.pid"
LOG="$HERE/target/serve.log"

is_up() { curl -sf "localhost:$PORT/api/eval" --data-binary '1' >/dev/null 2>&1; }

up() {
  if is_up; then echo "already up — http://localhost:$PORT"; return 0; fi
  JAR="$("$HERE/engine.sh")"
  [ -n "${KARATE_LICENSE_TEXT:-}" ] || export KARATE_LICENSE_PATH="$HERE/.karate/karate.lic"
  mkdir -p "$HERE/target"
  # a lane holds a whole run's exchanges in memory, and the deck lane is ~3,000 of them; the
  # default heap is enough for one branch and not for several in a row
  nohup java ${KARATE_SERVE_JAVA_OPTS:--Xmx2g} -jar "$JAR" serve "$HERE" --port "$PORT" \
       --report-dir target/karate-reports > "$LOG" 2>&1 &
  echo $! > "$PIDFILE"
  for _ in $(seq 1 60); do
    if is_up; then echo "ready — http://localhost:$PORT"; return 0; fi
    sleep 1
  done
  echo "ERROR: not ready in 60s:" >&2; tail -20 "$LOG" >&2; exit 1
}

down() {
  [ -f "$PIDFILE" ] && kill "$(cat "$PIDFILE")" 2>/dev/null || true
  rm -f "$PIDFILE"
  pkill -f "serve $HERE " 2>/dev/null || true
  echo "stopped."
}

case "${1:-up}" in
  up|start) up ;;
  down|stop) down ;;
  status) is_up && echo up || echo down ;;
  restart) down; sleep 1; up ;;
  *) echo "usage: ./serve.sh [up|down|status|restart]" >&2; exit 2 ;;
esac
