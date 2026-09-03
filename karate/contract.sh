#!/usr/bin/env bash
# contract.sh — the transport contract below the business rules: always JSON, never a 5xx.
set -euo pipefail
cd "$(dirname "$0")"
./ka.sh "
var r = File.call('/checks/contract-live.js', {baseUrl: '${QM_URL:-http://localhost:9981}'});
({probes:r.probes, ok:r.ok, violations:r.violations.length, first:r.violations.slice(0,4)})"
