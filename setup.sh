#!/usr/bin/env bash
# setup.sh - macOS / Linux. Installs the environment only (JDK 17+ and Maven).
# Tools already on the machine are reused; missing ones are downloaded to ./.tools (no sudo).
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
TOOLS="$ROOT/.tools"
JDK_DIR="$TOOLS/jdk"
MVN_DIR="$TOOLS/maven"
MIN_JAVA=17
JDK_VERSION=17
MAVEN_VERSION="3.9.9"
TEST_FILE="src/test/java/com/seminar/fcm/FcmFlowTest.java"

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
    die "'curl' or 'wget' is required to download files (e.g. sudo apt install curl)."
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

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Missing command '$1'. Install it first (e.g. sudo apt install $1)."; }

java_major() {
  local out
  out="$("$1" -version 2>&1 | awk -F'"' '/version/ {print $2; exit}')" || true
  [ -z "$out" ] && { echo 0; return; }
  case "$out" in
    1.*) echo "$out" | cut -d. -f2 ;;
    *)   echo "$out" | cut -d. -f1 | sed 's/[^0-9].*//' ;;
  esac
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

ensure_jdk() {
  if command -v java >/dev/null 2>&1 && command -v javac >/dev/null 2>&1; then
    local v; v="$(java_major "$(command -v java)")"
    if [ "${v:-0}" -ge "$MIN_JAVA" ]; then
      ok "JDK $v found on this machine - skipping install."
      return
    fi
    warn "JDK on this machine is version $v (< $MIN_JAVA) - using a portable JDK."
  fi

  local home=""
  for cand in "$JDK_DIR/Contents/Home" "$JDK_DIR"; do
    [ -x "$cand/bin/javac" ] && home="$cand" && break
  done

  if [ -z "$home" ]; then
    need_cmd tar
    say "Downloading JDK $JDK_VERSION (Temurin, $ADOPT_OS/$ADOPT_ARCH) ..."
    mkdir -p "$TOOLS"
    local archive="$TOOLS/jdk.tar.gz"
    download "https://api.adoptium.net/v3/binary/latest/${JDK_VERSION}/ga/${ADOPT_OS}/${ADOPT_ARCH}/jdk/hotspot/normal/eclipse" "$archive"
    rm -rf "$JDK_DIR"; mkdir -p "$JDK_DIR"
    tar -xzf "$archive" -C "$JDK_DIR" --strip-components=1
    rm -f "$archive"
    for cand in "$JDK_DIR/Contents/Home" "$JDK_DIR"; do
      [ -x "$cand/bin/javac" ] && home="$cand" && break
    done
    [ -n "$home" ] || die "JDK extracted but bin/javac was not found."
    ok "Portable JDK installed at $home"
  else
    ok "Using existing portable JDK at $home"
  fi

  export JAVA_HOME="$home"
  export PATH="$JAVA_HOME/bin:$PATH"
}

ensure_maven() {
  if command -v mvn >/dev/null 2>&1; then
    ok "Maven found on this machine - skipping install."
    return
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
    ok "Portable Maven installed at $MVN_DIR"
  else
    ok "Using existing portable Maven at $MVN_DIR"
  fi
  export PATH="$MVN_DIR/bin:$PATH"
}

ensure_project() {
  [ -f pom.xml ] || die "pom.xml not found. Run this script from the project root."

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

  if [ -f .gitignore ] && ! grep -qxF ".tools/" .gitignore; then
    printf '\n# portable tools downloaded by the setup scripts\n.tools/\n' >> .gitignore
  fi
}

say "Operating system: $ADOPT_OS / $ADOPT_ARCH"
ensure_jdk
ensure_maven
ensure_project

echo
java -version 2>&1 | head -1
mvn -v 2>&1 | head -1
echo
ok "Environment ready. Run the tests with: ./test.sh"
