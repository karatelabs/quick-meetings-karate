#!/usr/bin/env bash
# engine.sh — resolve the karate-agent jar and print its path. Never commits a jar.
#   KARATE_AGENT_JAR=<path>   use that jar as-is
#   else                      the pinned release asset, else the GHCR image's /jars/ copy
#   KARATE_ENGINE_STRICT=1    fail rather than fall back to the image
# The path and its sha256 go to stderr, so every run says which engine it graded: one version
# string has already meant two jars — a locally built one and the image's — and the difference
# was read as one engine behaving differently warm and cold.
set -euo pipefail
cd "$(dirname "$0")"
V="$(cat engine.version)"
JAR="lib/karate-agent-$V.jar"

# macOS has shasum, Linux has sha256sum
sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

resolved() { echo "engine: $1 sha256=$(sha256 "$1")" >&2; echo "$1"; exit 0; }

if [ -n "${KARATE_AGENT_JAR:-}" ]; then resolved "$KARATE_AGENT_JAR"; fi
if [ -f "$JAR" ]; then resolved "$PWD/$JAR"; fi

mkdir -p lib
URL="https://github.com/karatelabs/karate-addons/releases/download/agent-$V/karate-agent-$V.jar"
if curl -sfL -o "$JAR.tmp" "$URL"; then
  mv "$JAR.tmp" "$JAR"
  resolved "$PWD/$JAR"
fi
rm -f "$JAR.tmp"

IMAGE="${KARATE_AGENT_IMAGE:-ghcr.io/karatelabs/karate-agent:$V}"
# The asset for this version 404s, so the image is the branch every local run actually takes. CI
# needs it, but it is never the quiet one: a fallback nobody saw is how a developer's own build
# and the image's jar came to share a version string.
if [ "${KARATE_ENGINE_STRICT:-}" = 1 ]; then
  echo "engine: no release asset for agent-$V and KARATE_ENGINE_STRICT=1 — refusing $IMAGE" >&2
  exit 1
fi
echo "engine: WARNING no release asset for agent-$V — using the jar inside $IMAGE (set KARATE_AGENT_JAR to grade your own build)" >&2
docker pull -q "$IMAGE" >&2
CID="$(docker create "$IMAGE")"
trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT
docker cp "$CID:/jars/karate-agent-$V.jar" "$JAR" >&2
resolved "$PWD/$JAR"
