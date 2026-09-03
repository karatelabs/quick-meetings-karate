#!/usr/bin/env bash
# reset-mock.sh — the mock's counterpart to reset-sut.sh: back to the twin's root world,
# no meetings and exactly the three fixture users the twin names as ids 1, 2, 3.
set -euo pipefail
curl -sf -X POST "${QM_URL:-http://localhost:9981}/__reset" -d '' -H 'Content-Type: application/json'
