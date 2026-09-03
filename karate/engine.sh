#!/usr/bin/env bash
# engine.sh — resolve the karate-agent jar and print its path. Never commits a jar.
#   KARATE_AGENT_JAR=<path>   use that jar as-is
#   else                      the pinned release asset, else the GHCR image's /jars/ copy
set -euo pipefail
cd "$(dirname "$0")"
V="$(cat engine.version)"
JAR="lib/karate-agent-$V.jar"

if [ -n "${KARATE_AGENT_JAR:-}" ]; then echo "$KARATE_AGENT_JAR"; exit 0; fi
if [ -f "$JAR" ]; then echo "$PWD/$JAR"; exit 0; fi

mkdir -p lib
URL="https://github.com/karatelabs/karate-addons/releases/download/agent-$V/karate-agent-$V.jar"
if curl -sfL -o "$JAR.tmp" "$URL"; then
  mv "$JAR.tmp" "$JAR"
  echo "$PWD/$JAR"; exit 0
fi
rm -f "$JAR.tmp"

IMAGE="${KARATE_AGENT_IMAGE:-ghcr.io/karatelabs/karate-agent:$V}"
echo "no release asset for $V — extracting the jar from $IMAGE" >&2
docker pull -q "$IMAGE" >&2
CID="$(docker create "$IMAGE")"
trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT
docker cp "$CID:/jars/karate-agent-$V.jar" "$JAR" >&2
echo "$PWD/$JAR"
