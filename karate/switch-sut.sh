#!/usr/bin/env bash
# switch-sut.sh <branch> — check this repo out on a branch and restart the SUT on :9981.
set -euo pipefail
cd "$(dirname "$0")/.."
BR="$1"
./karate/app.sh down
git checkout -q "$BR"
echo "on $(git rev-parse --abbrev-ref HEAD)"
./karate/app.sh up
./karate/reset-sut.sh
