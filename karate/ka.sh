#!/usr/bin/env bash
# ka.sh — one line of JS on the served engine. usage: ./ka.sh '<js>'
curl -sf --max-time "${KA_TIMEOUT:-900}" "localhost:${KARATE_SERVE_PORT:-8099}/api/eval" --data-binary "$1"
