#!/usr/bin/env bash
# ka.sh — one line of JS on the served engine, unwrapped. usage: ./ka.sh '<js>'
set -euo pipefail
curl -sf --max-time "${KA_TIMEOUT:-900}" "localhost:${KARATE_SERVE_PORT:-8099}/api/eval" \
  --data-binary "$1" | python3 -c '
import json, sys
r = json.load(sys.stdin)
if r.get("command") == "error":
    sys.exit("%s: %s" % (r.get("name", "error"), r.get("payload")))
p = r.get("payload")
print(p if isinstance(p, str) else json.dumps(p, indent=2))
'
