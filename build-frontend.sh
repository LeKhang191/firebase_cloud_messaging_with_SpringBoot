#!/usr/bin/env bash
# Builds the React UI (frontend/) and copies it into Spring Boot's static folder.
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STATIC="$ROOT/src/main/resources/static"
command -v npm >/dev/null || { echo "Need Node.js 18+ (npm not found)"; exit 1; }
cd "$ROOT/frontend"
npm install --no-audit --no-fund
npm run build
rm -rf "$STATIC/assets"
cp -r dist/. "$STATIC/"
echo "Done. Reload the page to see the new UI."
