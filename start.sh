#!/usr/bin/env bash
# start.sh - One-click setup and launch for macOS/Linux.
# Installs missing tools, checks Firebase configuration, and starts the Spring Boot app.
set -Eeuo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

BUILD_FRONTEND=1
BUILD_ONLY=0
USE_TUNNEL=1
while [ "$#" -gt 0 ]; do
  case "$1" in
    --build-frontend) BUILD_FRONTEND=1 ;;
    --skip-build) BUILD_FRONTEND=0 ;;
    --build-only) BUILD_FRONTEND=1; BUILD_ONLY=1; USE_TUNNEL=0 ;;
    --tunnel|--public) USE_TUNNEL=1 ;;
    --local) USE_TUNNEL=0 ;;
    --help|-h)
      cat <<'HELP'
Usage: ./start.sh [options]
  (default)         Build frontend, start Spring Boot, and create a public Cloudflare link
  --local           Build frontend and run locally without a public tunnel
  --skip-build      Skip frontend build but still start Spring Boot and tunnel
  --build-frontend  Explicitly build frontend (already the default)
  --build-only      Build frontend and exit without starting the app/tunnel
  --tunnel, --public  Explicitly enable the temporary Cloudflare Quick Tunnel
  --help            Show this help

ADMIN_KEY is loaded from .env (created automatically if missing).
A public tunnel requires an ADMIN_KEY of at least 16 characters.
HELP
      exit 0 ;;
    *) printf '[error] Unknown option: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

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
ENV_FILE="$ROOT/.env"
CLOUDFLARED=""
APP_PID=""
TUNNEL_PID=""

say()  { printf '\033[1;36m[start]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ ok ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

download() {
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --progress-bar "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -q "$1" -O "$2"
  else
    die "'curl' or 'wget' is required to download cloudflared."
  fi
}

open_browser() {
  local target="${1:-$URL}"
  if command -v open >/dev/null 2>&1; then
    open "$target" >/dev/null 2>&1 || true
  elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$target" >/dev/null 2>&1 || true
  else
    warn "Could not detect a browser opener. Open $target manually."
  fi
}

load_admin_key() {
  local line value="" loaded=""
  if [ ! -f "$ENV_FILE" ]; then
    say "No .env found; generating a stable random ADMIN_KEY."
    if command -v openssl >/dev/null 2>&1; then
      loaded="$(openssl rand -hex 32)"
    elif command -v python3 >/dev/null 2>&1; then
      loaded="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
    else
      die "Cannot generate ADMIN_KEY: install openssl or python3, or create .env manually."
    fi
    [ -n "$loaded" ] || die "Could not generate ADMIN_KEY."
    (umask 077; printf 'ADMIN_KEY=%s\n' "$loaded" > "$ENV_FILE")
    chmod 600 "$ENV_FILE" 2>/dev/null || true
    ok "Created .env with a stable random ADMIN_KEY. Keep it private."
  fi

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%$'\r'}"
    case "$line" in ''|\#*|[[:space:]]\#*) continue ;; esac
    if [[ "$line" =~ ^[[:space:]]*ADMIN_KEY[[:space:]]*=(.*)$ ]]; then
      value="${BASH_REMATCH[1]}"
      value="$(printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      if [[ "$value" == \"*\" ]]; then value="${value:1:${#value}-2}"; fi
      if [[ "$value" == \'*\' ]]; then value="${value:1:${#value}-2}"; fi
      loaded="$value"
      break
    fi
  done < "$ENV_FILE"

  [ -n "$loaded" ] || die "ADMIN_KEY is missing or empty in .env. Add ADMIN_KEY=your-long-random-secret."
  export ADMIN_KEY="$loaded"
  chmod 600 "$ENV_FILE" 2>/dev/null || true
  say "Loaded ADMIN_KEY from .env."
  if [ "$USE_TUNNEL" -eq 1 ] && [ "${#ADMIN_KEY}" -lt 16 ]; then
    die "ADMIN_KEY must contain at least 16 characters when using a public tunnel."
  fi
}

ensure_cloudflared() {
  if command -v cloudflared >/dev/null 2>&1; then
    CLOUDFLARED="$(command -v cloudflared)"
  elif [ -x "$TOOLS/cloudflared" ]; then
    CLOUDFLARED="$TOOLS/cloudflared"
  else
    local os arch url archive
    case "$(uname -s)" in
      Darwin*) os="darwin" ;;
      Linux*) os="linux" ;;
      *) die "Cloudflare Tunnel is not supported on $(uname -s) by this script." ;;
    esac
    case "$(uname -m)" in
      arm64|aarch64) arch="arm64" ;;
      x86_64|amd64) arch="amd64" ;;
      *) die "Unsupported CPU architecture for cloudflared: $(uname -m)." ;;
    esac
    mkdir -p "$TOOLS"
    if [ "$os" = "darwin" ]; then
      archive="$TOOLS/cloudflared.tgz"
      url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-${arch}.tgz"
      say "Downloading cloudflared for macOS (${arch}) from Cloudflare releases..."
      download "$url" "$archive"
      tar -xzf "$archive" -C "$TOOLS"
      rm -f "$archive"
      [ -f "$TOOLS/cloudflared" ] || die "The cloudflared archive did not contain the expected binary."
    else
      CLOUDFLARED="$TOOLS/cloudflared"
      url="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}"
      say "Downloading cloudflared for Linux (${arch}) from Cloudflare releases..."
      download "$url" "$CLOUDFLARED"
    fi
    chmod 700 "$TOOLS/cloudflared"
    CLOUDFLARED="$TOOLS/cloudflared"
  fi
  "$CLOUDFLARED" --version >/dev/null 2>&1 || die "cloudflared was found/downloaded but failed its version check."
  ok "cloudflared is ready: $CLOUDFLARED"
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
  # Portable numeric comparison for dotted versions; works with macOS BSD tools.
  local v1="$1" v2="$2" a1 a2 a3 b1 b2 b3
  IFS=. read -r a1 a2 a3 <<< "$v1"
  IFS=. read -r b1 b2 b3 <<< "$v2"
  a1="${a1:-0}"; a2="${a2:-0}"; a3="${a3:-0}"
  b1="${b1:-0}"; b2="${b2:-0}"; b3="${b3:-0}"
  [ "$a1" -gt "$b1" ] && return 0
  [ "$a1" -lt "$b1" ] && return 1
  [ "$a2" -gt "$b2" ] && return 0
  [ "$a2" -lt "$b2" ] && return 1
  [ "$a3" -ge "$b3" ]
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
load_admin_key

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
      if [ "$(uname -s)" = "Darwin" ] && [ -x /usr/libexec/java_home ]; then
        JAVA_HOME="$(/usr/libexec/java_home -v "$jv" 2>/dev/null || true)"
      fi
      if [ -z "${JAVA_HOME:-}" ] || [ ! -x "$JAVA_HOME/bin/java" ]; then
        javac_path="$(command -v javac)"
        JAVA_HOME="$(dirname "$(dirname "$javac_path")")"
        if [ ! -x "$JAVA_HOME/bin/java" ] && [ -x "$JAVA_HOME/Contents/Home/bin/java" ]; then
          JAVA_HOME="$JAVA_HOME/Contents/Home"
        fi
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

if [ "$BUILD_FRONTEND" -eq 1 ]; then
  command -v node >/dev/null 2>&1 || die "Node.js 18+ is required to build frontend (node not found)."
  node_major="$(node --version | sed 's/^v//' | cut -d. -f1)"
  [[ "$node_major" =~ ^[0-9]+$ ]] && [ "$node_major" -ge 18 ] || die "Node.js 18+ is required; found $(node --version)."
  command -v npm >/dev/null 2>&1 || die "npm is required to build the frontend."
  say "Building React frontend..."
  bash "$ROOT/build-frontend.sh"
  ok "Frontend build completed."
  if [ "$BUILD_ONLY" -eq 1 ]; then exit 0; fi
fi

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
  if [ "$USE_TUNNEL" -eq 1 ]; then
    die "Port $PORT is already in use. Stop the existing app and relaunch start.sh so ADMIN_KEY is applied before opening a public tunnel."
  fi
  warn "Port $PORT is already in use (the app may already be running)."
  say "Opening browser: $URL"
  open_browser "$URL"
  exit 0
fi

if [ "$USE_TUNNEL" -eq 1 ]; then
  ensure_cloudflared
fi

echo
say "Starting Spring Boot. The first run may take a few minutes to download dependencies."
say "Press Ctrl+C to stop the application."
"$MVN" -B spring-boot:run &
APP_PID=$!

cleanup() {
  if [ -n "${TUNNEL_PID:-}" ] && kill -0 "$TUNNEL_PID" 2>/dev/null; then
    kill "$TUNNEL_PID" 2>/dev/null || true
    wait "$TUNNEL_PID" 2>/dev/null || true
  fi
  if [ -n "${APP_PID:-}" ] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

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

OPEN_URL="$URL"
if [ "$USE_TUNNEL" -eq 1 ]; then
  TUNNEL_LOG="$TOOLS/cloudflared-quick-tunnel.log"
  : > "$TUNNEL_LOG"
  say "Starting Cloudflare Quick Tunnel..."
  "$CLOUDFLARED" tunnel --url "$URL" >"$TUNNEL_LOG" 2>&1 &
  TUNNEL_PID=$!
  tunnel_deadline=$((SECONDS + 90))
  while [ "$SECONDS" -lt "$tunnel_deadline" ]; do
    if ! kill -0 "$TUNNEL_PID" 2>/dev/null; then break; fi
    PUBLIC_URL="$(grep -Eo 'https://[[:alnum:].-]+\.trycloudflare\.com' "$TUNNEL_LOG" | head -n 1 || true)"
    if [ -n "$PUBLIC_URL" ]; then break; fi
    sleep 1
  done
  PUBLIC_URL="$(grep -Eo 'https://[[:alnum:].-]+\.trycloudflare\.com' "$TUNNEL_LOG" | head -n 1 || true)"
  if [ -z "$PUBLIC_URL" ]; then
    warn "Cloudflare did not provide a public URL. Recent tunnel output:"
    tail -n 30 "$TUNNEL_LOG" 2>/dev/null || true
    die "Could not obtain a Cloudflare Quick Tunnel URL. Check network access and retry."
  fi
  OPEN_URL="$PUBLIC_URL"
  echo
  ok "CLOUDFLARE PUBLIC LINK: $PUBLIC_URL"
  warn "Anyone with this link can open the app; admin APIs require the ADMIN_KEY from .env."
  warn "Quick Tunnel links are temporary and change after restarting."
fi

echo
ok "APPLICATION IS RUNNING: $OPEN_URL"
say "Opening browser."
open_browser "$OPEN_URL"
wait "$APP_PID"
