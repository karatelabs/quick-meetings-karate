#!/usr/bin/env bash
# app.sh — build and run quick-meetings (the SUT at the repo root) on :9981. [up|down|status]
# The readiness probe must not mutate: it runs after reset-sut.sh in CI and in the README.
set -euo pipefail
cd "$(dirname "$0")/.."
SUT="$(pwd)"
PORT="${QM_PORT:-9981}"
LOG="$SUT/karate/target/app.log"
PIDFILE="$SUT/karate/.app.pid"

is_up() { curl -sf -o /dev/null "http://localhost:$PORT/v3/api-docs" 2>/dev/null; }

listener() { lsof -t -nP -iTCP:"$PORT" -sTCP:LISTEN 2>/dev/null || true; }

# only ever kill what this script started: a recorded pid that still looks like our app
ours() {
  ps -p "$1" -o command= 2>/dev/null | grep -qE 'spring-boot:run|quickmeetings\.QuickmeetingsApplication'
}

up() {
  if is_up; then echo "already up — :$PORT"; return 0; fi
  mkdir -p "$SUT/karate/target"
  ( cd "$SUT" && nohup mvn -q spring-boot:run > "$LOG" 2>&1 & echo $! > "$PIDFILE" )
  for _ in $(seq 1 120); do
    if is_up; then
      # devtools forces spring-boot:run to fork, so the serving JVM is not the maven pid
      listener >> "$PIDFILE"
      echo "up — :$PORT"; return 0
    fi
    sleep 2
  done
  echo "ERROR: did not come up" >&2; tail -30 "$LOG" >&2; exit 1
}

down() {
  if [ -f "$PIDFILE" ]; then
    while read -r pid; do
      [ -n "$pid" ] && ours "$pid" || continue
      kill "$pid" 2>/dev/null || true
      for _ in $(seq 1 30); do ps -p "$pid" > /dev/null 2>&1 || break; sleep 1; done
      ps -p "$pid" > /dev/null 2>&1 && kill -9 "$pid" 2>/dev/null || true
    done < "$PIDFILE"
    rm -f "$PIDFILE"
  fi
  echo "stopped."
}

case "${1:-up}" in
  up|start) up ;;
  down|stop) down ;;
  status) is_up && echo up || echo down ;;
  *) echo "usage: ./app.sh [up|down|status]" >&2; exit 2 ;;
esac
