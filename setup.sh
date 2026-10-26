#!/usr/bin/env bash
# setup.sh - macOS / Linux. Installs the environment only (JDK 17-21 and Maven).
# Tools already on the machine are reused; missing ones are downloaded to ./.tools (no sudo).
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
TOOLS="$ROOT/.tools"
JDK_DIR="$TOOLS/jdk"
MVN_DIR="$TOOLS/maven"
MIN_JAVA=17
MAX_JAVA=21
JDK_VERSION=17
MAVEN_VERSION="3.9.9"
TEST_FILE="src/test/java/com/seminar/fcm/FcmFlowTest.java"
ADMIN_TEST_FILE="src/test/java/com/seminar/fcm/AdminKeyTest.java"

say()  { printf '\033[1;36m[setup]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ ok  ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn ]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

download() {
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --progress-bar "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --show-progress "$1" -O "$2"
  else
    die "'curl' or 'wget' is required to download files (e.g. brew install curl / apt install curl)."
  fi
}

download_any() {
  local file="$1"; shift
  local u
  for u in "$@"; do
    say "Trying: $u"
    if download "$u" "$file"; then return 0; fi
    warn "Failed: $u"
    rm -f "$file"
  done
  die "Could not download from any source. Check your network / VPN / proxy / firewall."
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command '$1'. Install it first."; }

java_major() {
  local out
  out="$("$1" -version 2>&1 | awk -F'"' '/version/ {print $2; exit}')" || true
  [ -z "$out" ] && { echo 0; return; }
  case "$out" in
    1.*) echo "$out" | cut -d. -f2 ;;
    *)   echo "$out" | cut -d. -f1 | sed 's/[^0-9].*//' ;;
  esac
}

javac_major() {
  local out
  out="$("$1" -version 2>&1 | awk 'NR==1 {for (i=1; i<=NF; i++) if ($i ~ /^[0-9]+([.][0-9]+)*/) {print $i; exit}}')" || true
  [ -z "$out" ] && { echo 0; return; }
  echo "$out" | cut -d. -f1 | sed 's/[^0-9].*//'
}

case "$(uname -s)" in
  Linux*)  ADOPT_OS="linux"; [ -f /etc/alpine-release ] && ADOPT_OS="alpine-linux" ;;
  Darwin*) ADOPT_OS="mac" ;;
  *) die "Operating system '$(uname -s)' is not supported by .sh scripts. On Windows use setup.bat" ;;
esac

case "$(uname -m)" in
  x86_64|amd64)  ADOPT_ARCH="x64" ;;
  arm64|aarch64) ADOPT_ARCH="aarch64" ;;
  *) die "CPU architecture '$(uname -m)' is not supported." ;;
esac

locate_jdk_home() {
  local target_dir="$1"
  local javac_bin
  javac_bin="$(find "$target_dir" -type f -name javac -print -quit 2>/dev/null)"
  if [ -n "$javac_bin" ]; then
    dirname "$(dirname "$javac_bin")"
  fi
}

ensure_jdk() {
  if [ "${FCM_FORCE_PORTABLE_TOOLS:-0}" != "1" ] && command -v java >/dev/null 2>&1 && command -v javac >/dev/null 2>&1; then
    local java_v javac_v home javac_path
    java_v="$(java_major "$(command -v java)")"
    javac_v="$(javac_major "$(command -v javac)")"
    if [ "${java_v:-0}" -ge "$MIN_JAVA" ] && [ "${java_v:-0}" -le "$MAX_JAVA" ] && [ "$java_v" = "$javac_v" ]; then
      if [ "$ADOPT_OS" = "mac" ] && [ -x /usr/libexec/java_home ]; then
        home="$(/usr/libexec/java_home -v "$java_v" 2>/dev/null || true)"
      else
        javac_path="$(readlink -f "$(command -v javac)" 2>/dev/null || command -v javac)"
        home="$(dirname "$(dirname "$javac_path")")"
      fi
      if [ -n "${home:-}" ] && [ -x "$home/bin/java" ] && [ -x "$home/bin/javac" ]; then
        export JAVA_HOME="$home"
        export PATH="$JAVA_HOME/bin:$PATH"
      fi
      ok "JDK $java_v found on this machine - skipping JDK download."
      return
    fi
    warn "System Java/JDK is missing, mismatched, or outside versions $MIN_JAVA-$MAX_JAVA; checking portable JDK."
  fi

  local home=""
  if [ -d "$JDK_DIR" ]; then
    home="$(locate_jdk_home "$JDK_DIR")"
  fi

  if [ -z "$home" ] || [ ! -x "$home/bin/java" ] || [ ! -x "$home/bin/javac" ]; then
    need_cmd tar
    say "Downloading JDK $JDK_VERSION (Temurin, $ADOPT_OS/$ADOPT_ARCH) ..."
    mkdir -p "$TOOLS"
    local archive="$TOOLS/jdk.tar.gz"
    download "https://api.adoptium.net/v3/binary/latest/${JDK_VERSION}/ga/${ADOPT_OS}/${ADOPT_ARCH}/jdk/hotspot/normal/eclipse" "$archive"
    rm -rf "$JDK_DIR"; mkdir -p "$JDK_DIR"
    tar -xzf "$archive" -C "$JDK_DIR" --strip-components=1
    rm -f "$archive"

    home="$(locate_jdk_home "$JDK_DIR")"
    [ -n "$home" ] && [ -x "$home/bin/java" ] && [ -x "$home/bin/javac" ] || die "JDK extracted but java/javac were not found."

    if [ "$ADOPT_OS" = "mac" ] && command -v xattr >/dev/null 2>&1; then
      xattr -dr com.apple.quarantine "$JDK_DIR" 2>/dev/null || true
    fi
    ok "Portable JDK installed at $home"
  else
    ok "Using existing portable JDK at $home"
  fi

  local portable_v
  portable_v="$(java_major "$home/bin/java")"
  [ "${portable_v:-0}" -ge "$MIN_JAVA" ] && [ "${portable_v:-0}" -le "$MAX_JAVA" ] || die "Portable JDK version must be $MIN_JAVA-$MAX_JAVA; found $portable_v."
  export JAVA_HOME="$home"
  export PATH="$JAVA_HOME/bin:$PATH"
}

maven_major_minor_patch() {
  "$1" -v 2>&1 | awk '/Apache Maven/ {print $3; exit}'
}

maven_is_compatible() {
  local version="$1" major minor patch
  [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]] || return 1
  major="${BASH_REMATCH[1]}"; minor="${BASH_REMATCH[2]}"; patch="${BASH_REMATCH[3]}"
  [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && { [ "$minor" -gt 6 ] || { [ "$minor" -eq 6 ] && [ "$patch" -ge 3 ]; }; }; }
}

ensure_maven() {
  local system_mvn="" version=""
  if [ "${FCM_FORCE_PORTABLE_TOOLS:-0}" != "1" ] && command -v mvn >/dev/null 2>&1; then
    system_mvn="$(command -v mvn)"
    version="$(maven_major_minor_patch "$system_mvn" || true)"
    if maven_is_compatible "$version"; then
      ok "Maven $version found on this machine - skipping Maven download."
      return
    fi
    warn "System Maven version '${version:-unknown}' is missing or too old; checking portable Maven."
  fi
  if [ ! -x "$MVN_DIR/bin/mvn" ]; then
    need_cmd tar
    say "Downloading Maven $MAVEN_VERSION ..."
    mkdir -p "$TOOLS"
    local archive="$TOOLS/maven.tar.gz"
    download_any "$archive" \
      "https://repo.maven.apache.org/maven2/org/apache/maven/apache-maven/${MAVEN_VERSION}/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
      "https://repo1.maven.org/maven2/org/apache/maven/apache-maven/${MAVEN_VERSION}/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
      "https://downloads.apache.org/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
      "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
    rm -rf "$MVN_DIR"; mkdir -p "$MVN_DIR"
    tar -xzf "$archive" -C "$MVN_DIR" --strip-components=1
    rm -f "$archive"
    if [ "$ADOPT_OS" = "mac" ] && command -v xattr >/dev/null 2>&1; then
      xattr -dr com.apple.quarantine "$MVN_DIR" 2>/dev/null || true
    fi
    ok "Portable Maven installed at $MVN_DIR"
  fi
  version="$(maven_major_minor_patch "$MVN_DIR/bin/mvn" || true)"
  maven_is_compatible "$version" || die "Portable Maven is too old or invalid (found '${version:-unknown}'; need Maven 3.6.3 or newer)."
  export PATH="$MVN_DIR/bin:$PATH"
}

ensure_project() {
  [ -f pom.xml ] || die "pom.xml not found. Run this script from the project root."

  tr -d '\r' < pom.xml > pom.xml.tmp && mv pom.xml.tmp pom.xml

  if ! grep -q "spring-boot-starter-test" pom.xml; then
    say "pom.xml has no spring-boot-starter-test - adding it."
    cp pom.xml pom.xml.bak
    awk '
      !done && /<\/dependencies>/ {
        print "        <dependency>"
        print "            <groupId>org.springframework.boot</groupId>"
        print "            <artifactId>spring-boot-starter-test</artifactId>"
        print "            <scope>test</scope>"
        print "        </dependency>"
        done=1
      }
      { print }
    ' pom.xml.bak > pom.xml
    ok "Dependency added (original saved as pom.xml.bak)."
  fi

  [ -f "$TEST_FILE" ] || warn "$TEST_FILE not found - copy FcmFlowTest.java there before running tests."
  [ -f "$ADMIN_TEST_FILE" ] || warn "$ADMIN_TEST_FILE not found - admin-key security tests will be missing."

  [ -f .gitignore ] || : > .gitignore
  ensure_ignore_pattern() {
    local pattern="$1"
    grep -qxF -- "$pattern" .gitignore || printf '%s\n' "$pattern" >> .gitignore
  }
  ensure_ignore_pattern '.env'
  ensure_ignore_pattern '.env.*'
  ensure_ignore_pattern '!.env.example'
  ensure_ignore_pattern '.tools/'
  ensure_ignore_pattern 'firebase-service-account.json'
  ensure_ignore_pattern 'src/main/resources/static/firebase-config.js'

  if command -v git >/dev/null 2>&1 \
      && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
      && git -C "$ROOT" ls-files --error-unmatch -- .env >/dev/null 2>&1; then
    warn '.env is already tracked by Git. .gitignore cannot untrack it; run: git rm --cached .env'
    warn 'If that key was pushed to a public repository, rotate ADMIN_KEY.'
  fi
}

say "Operating system: $ADOPT_OS / $ADOPT_ARCH"
ensure_jdk
ensure_maven
ensure_project

echo
java -version 2>&1 | sed -n '1p'
mvn -v 2>&1 | sed -n '1p'
echo
ok "Environment ready. Run the tests with: ./test.sh"