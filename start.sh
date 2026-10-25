#!/usr/bin/env bash
# start.sh - One-click setup and launch for macOS/Linux.
# Installs missing tools, checks Firebase configuration, and starts the Spring Boot app.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

TOOLS="$ROOT/.tools"
JDK_DIR="$TOOLS/jdk"
MAVEN_DIR="$TOOLS/maven"
MIN_JAVA=17
MAX_JAVA=21
MAVEN_MIN="3.6.3"
PORT=8080
URL="http://localhost:$PORT"
SERVICE_ACCOUNT="$ROOT/firebase-service-account.json"
WEB_CONFIG="$ROOT/src/main/resources/static/firebase-config.js"
WEB_CONFIG_SAMPLE="$ROOT/src/main/resources/static/firebase-config.example.js"

say()  { printf '\033[1;36m[start]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ ok ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

open_browser() {
  if command -v open >/dev/null 2>&1; then
    open "$URL" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL" >/dev/null 2>&1 || true
  else
    warn "Could not detect a browser opener. Open $URL manually."
  fi
}

java_major() {
  local out
  out="$("$1" -version 2>&1 | awk -F'"' '/version/ {print $2; exit}')" || true
  [ -n "$out" ] || { echo 0; return; }
  case "$out" in
    1.*) echo "$out" | cut -d. -f2 ;;
    *) echo "$out" | cut -d. -f1 | sed 's/[^0-9].*//' ;;
  esac
}

javac_major() {
  local out
  out="$("$1" -version 2>&1 | awk '{print $2; exit}')" || true
  [ -n "$out" ] || { echo 0; return; }
  echo "$out" | cut -d. -f1 | sed 's/[^0-9].*//'
}

maven_version() {
  "$1" -v 2>&1 | awk '/Apache Maven/ {print $3; exit}'
}

version_ge() {
  # Compare numeric dotted versions, e.g. 3.9.9 >= 3.6.3.
  [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" = "$2" ]
}

find_portable_jdk_home() {
  local javac_bin
  javac_bin="$(find "$JDK_DIR" -type f -name javac -print -quit 2>/dev/null || true)"
  [ -n "$javac_bin" ] && dirname "$(dirname "$javac_bin")"
}

is_port_busy() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1
  elif command -v nc >/dev/null 2>&1; then
    nc -z 127.0.0.1 "$PORT" >/dev/null 2>&1
  else
    curl -fsS --max-time 2 "$URL" >/dev/null 2>&1
  fi
}

say "FCM + Spring Boot demo: setup and launch"
[ -f "$ROOT/pom.xml" ] || die "pom.xml not found. Keep start.sh in the project root."

# Reuse the project's setup script so tool installation follows the same rules.
if [ -f "$ROOT/setup.sh" ]; then
  say "Checking the Java and Maven environment..."
  bash "$ROOT/setup.sh"
else
  die "setup.sh not found. Cannot install or validate the required tools."
fi

# setup.sh exports do not persist in this process, so select the compatible tools again.
if [ "${FCM_FORCE_PORTABLE_TOOLS:-0}" != "1" ] && command -v java >/dev/null 2>&1 && command -v javac >/dev/null 2>&1; then
  jv="$(java_major "$(command -v java)")"
  cv="$(javac_major "$(command -v javac)")"
  if [ "$jv" -ge "$MIN_JAVA" ] && [ "$jv" -le "$MAX_JAVA" ] && [ "$jv" -eq "$cv" ]; then
    export JAVA_HOME
    if [ -z "${JAVA_HOME:-}" ] || [ ! -x "$JAVA_HOME/bin/java" ]; then
      JAVA_HOME="$(dirname "$(dirname "$(command -v javac)")")"
      # macOS system Java installations can require the JDK's Contents/Home directory.
      if [ ! -x "$JAVA_HOME/bin/java" ] && [ -x "$JAVA_HOME/Contents/Home/bin/java" ]; then
        JAVA_HOME="$JAVA_HOME/Contents/Home"
      fi
      export JAVA_HOME
    fi
    ok "Using system JDK $jv."
  else
    portable_home="$(find_portable_jdk_home)"
    [ -n "$portable_home" ] || die "Could not locate the portable JDK. Run ./setup.sh again."
    export JAVA_HOME="$portable_home"
    export PATH="$JAVA_HOME/bin:$PATH"
    ok "Using portable JDK at $JAVA_HOME."
  fi
else
  portable_home="$(find_portable_jdk_home)"
  [ -n "$portable_home" ] || die "Could not locate a suitable JDK. Run ./setup.sh again."
  export JAVA_HOME="$portable_home"
  export PATH="$JAVA_HOME/bin:$PATH"
  ok "Using portable JDK at $JAVA_HOME."
fi

if [ "${FCM_FORCE_PORTABLE_TOOLS:-0}" != "1" ] && command -v mvn >/dev/null 2>&1; then
  mvn_cmd="$(command -v mvn)"
  mvn_ver="$(maven_version "$mvn_cmd" || true)"
  if [ -n "$mvn_ver" ] && version_ge "$mvn_ver" "$MAVEN_MIN"; then
    ok "Using system Maven $mvn_ver."
  else
    warn "System Maven is missing or too old; using portable Maven."
    mvn_cmd="$MAVEN_DIR/bin/mvn"
  fi
else
  mvn_cmd="$MAVEN_DIR/bin/mvn"
fi
[ -x "$mvn_cmd" ] || die "Maven was not found. Run ./setup.sh again."
export PATH="$(dirname "$mvn_cmd"):$PATH"
# Use an explicit Maven executable to ensure the selected toolchain is used.
MVN="$mvn_cmd"

ensure_service_account() {
  if [ -f "$SERVICE_ACCOUNT" ]; then
    if command -v python3 >/dev/null 2>&1; then
      if ! python3 - "$SERVICE_ACCOUNT" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
    if data.get("type") != "service_account" or not data.get("private_key"):
        raise ValueError("not a Firebase service-account key")
except Exception as exc:
    print(f"[error] Invalid firebase-service-account.json: {exc}", file=sys.stderr)
    sys.exit(1)
PY
      then
        die "Fix firebase-service-account.json and run again."
      fi
    fi
    ok "firebase-service-account.json found."
    return
  fi

  warn "firebase-service-account.json is missing (server-side private key)."
  say "Open Firebase Console > Project settings > Service accounts > Generate new private key."
  open "https://console.firebase.google.com/" >/dev/null 2>&1 || true
  while true; do
    printf "Enter the path to the service-account JSON file (or q to quit): "
    IFS= read -r input || die "Cancelled."
    input="${input#\"}"; input="${input%\"}"
    [ "$input" = "q" ] || [ "$input" = "Q" ] && die "Cancelled."
    [ -n "$input" ] || continue
    [ -f "$input" ] || { warn "File not found: $input"; continue; }
    if command -v python3 >/dev/null 2>&1; then
      if ! python3 - "$input" <<'PY'
import json, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        data = json.load(f)
    if data.get("type") != "service_account" or not data.get("private_key"):
        raise ValueError("not a service-account key")
except Exception:
    sys.exit(1)
PY
      then
        warn "That file is not a valid service-account JSON. Try again."
        continue
      fi
    fi
    cp "$input" "$SERVICE_ACCOUNT"
    chmod 600 "$SERVICE_ACCOUNT" 2>/dev/null || true
    ok "Saved firebase-service-account.json."
    return
  done
}

ensure_web_config() {
  if [ ! -f "$WEB_CONFIG" ]; then
    [ -f "$WEB_CONFIG_SAMPLE" ] || die "firebase-config.example.js is missing."
    cp "$WEB_CONFIG_SAMPLE" "$WEB_CONFIG"
    say "Created firebase-config.js from the example."
  fi

  while grep -q 'YOUR_' "$WEB_CONFIG"; do
    warn "firebase-config.js still contains placeholder values (YOUR_...)."
    say "Fill in your Firebase Web App settings and the VAPID key."
    if command -v open >/dev/null 2>&1; then
      open -e "$WEB_CONFIG" >/dev/null 2>&1 || true
    elif command -v xdg-open >/dev/null 2>&1; then
      xdg-open "$WEB_CONFIG" >/dev/null 2>&1 || true
    fi
    printf "After saving firebase-config.js, press Enter to check again (or q to quit): "
    IFS= read -r input || die "Cancelled."
    [ "$input" = "q" ] || [ "$input" = "Q" ] && die "Cancelled."
  done
  ok "firebase-config.js is filled in."
}

check_project_match() {
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$SERVICE_ACCOUNT" "$WEB_CONFIG" <<'PY'
import json, re, sys
try:
    with open(sys.argv[1], encoding="utf-8") as f:
        project_id = json.load(f).get("project_id")
    with open(sys.argv[2], encoding="utf-8") as f:
        config = f.read()
    match = re.search(r'projectId\s*:\s*["\']([^"\']+)', config)
    if project_id and match:
        if project_id != match.group(1):
            print(f"[warn] projectId in firebase-config.js ({match.group(1)}) differs from service account project_id ({project_id}).")
            print("[warn] Both files must belong to the same Firebase project.")
        else:
            print(f"[ ok ] Firebase projectId matches ({project_id}).")
except Exception:
    pass
PY
  fi
}

ensure_service_account
ensure_web_config
check_project_match

if is_port_busy; then
  warn "Port $PORT is already in use (the app may already be running)."
  say "Opening browser: $URL"
  open_browser
  exit 0
fi

echo
say "Starting Spring Boot. The first run may take a few minutes to download dependencies."
say "Press Ctrl+C to stop the application."
"$MVN" -B spring-boot:run &
APP_PID=$!

cleanup() {
  if kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
}
trap cleanup INT TERM

deadline=$((SECONDS + 600))
app_ready=0
while [ "$SECONDS" -lt "$deadline" ]; do
  if ! kill -0 "$APP_PID" 2>/dev/null; then
    if wait "$APP_PID"; then code=0; else code=$?; fi
    die "Spring Boot exited before port $PORT became available (exit code $code)."
  fi
  if is_port_busy; then
    app_ready=1
    break
  fi
  sleep 2
done

if [ "$app_ready" -ne 1 ]; then
  die "Application did not start within 10 minutes. Review the errors above."
fi

echo
ok "APPLICATION IS RUNNING: $URL"
say "Opening browser."
open_browser
wait "$APP_PID"
