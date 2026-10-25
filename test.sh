#!/usr/bin/env bash
# =============================================================================
#  test.sh  -  macOS / Linux
#  ONLY RUNS THE AUTOTEST (mvn test). Installs nothing.
#  If JDK/Maven is missing, run ./setup.sh first.
#
#  Usage:
#    ./test.sh                              # run all tests
#    ./test.sh -Dtest=FcmFlowTest test      # run only the FcmFlowTest class
#    ./test.sh -Dtest=FcmFlowTest#fullFlow_registerThenOrderThenSelfCleaning test   # run a single test method
# =============================================================================
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
TOOLS="$ROOT/.tools"
MIN_JAVA=17
MAX_JAVA=21
TEST_FILE="src/test/java/com/seminar/fcm/FcmFlowTest.java"

say()  { printf '\033[1;36m[test ]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m[ ok  ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn ]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

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

locate_jdk_home() {
  local target_dir="$1"
  local javac_bin
  javac_bin="$(find "$target_dir" -type f -name javac -print -quit 2>/dev/null)"
  if [ -n "$javac_bin" ]; then
    dirname "$(dirname "$javac_bin")"
  fi
}

# ---------------------------------------------------------------- locate a suitable JDK (17-21)
use_jdk() {
  if [ "${FCM_FORCE_PORTABLE_TOOLS:-0}" != "1" ] && command -v java >/dev/null 2>&1 && command -v javac >/dev/null 2>&1; then
    local java_v javac_v home javac_path
    java_v="$(java_major "$(command -v java)")"
    javac_v="$(javac_major "$(command -v javac)")"
    if [ "${java_v:-0}" -ge "$MIN_JAVA" ] && [ "${java_v:-0}" -le "$MAX_JAVA" ] && [ "$java_v" = "$javac_v" ]; then
      if [ "$(uname -s)" = "Darwin" ] && [ -x /usr/libexec/java_home ]; then
        home="$(/usr/libexec/java_home -v "$java_v" 2>/dev/null || true)"
      else
        javac_path="$(readlink -f "$(command -v javac)" 2>/dev/null || command -v javac)"
        home="$(dirname "$(dirname "$javac_path")")"
      fi
      if [ -n "${home:-}" ] && [ -x "$home/bin/java" ] && [ -x "$home/bin/javac" ]; then
        export JAVA_HOME="$home"
        export PATH="$JAVA_HOME/bin:$PATH"
      fi
      ok "Use system JDK $java_v."
      return
    fi
    warn "System Java/JDK is missing, mismatched, or outside versions $MIN_JAVA-$MAX_JAVA."
  fi

  local home=""
  if [ -d "$TOOLS/jdk" ]; then home="$(locate_jdk_home "$TOOLS/jdk")"; fi
  if [ -n "$home" ] && [ -x "$home/bin/java" ] && [ -x "$home/bin/javac" ]; then
    local v; v="$(java_major "$home/bin/java")"
    if [ "${v:-0}" -ge "$MIN_JAVA" ] && [ "${v:-0}" -le "$MAX_JAVA" ]; then
      export JAVA_HOME="$home"
      export PATH="$JAVA_HOME/bin:$PATH"
      ok "Use portable JDK $v: $home"
      return
    fi
  fi
  die "No suitable JDK $MIN_JAVA-$MAX_JAVA found. Please run: ./setup.sh"
}

maven_is_compatible() {
  local version="$1" major minor patch
  [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]] || return 1
  major="${BASH_REMATCH[1]}"; minor="${BASH_REMATCH[2]}"; patch="${BASH_REMATCH[3]}"
  [ "$major" -gt 3 ] || { [ "$major" -eq 3 ] && { [ "$minor" -gt 6 ] || { [ "$minor" -eq 6 ] && [ "$patch" -ge 3 ]; }; }; }
}

maven_version() {
  "$1" -v 2>&1 | awk '/Apache Maven/ {print $3; exit}'
}

use_maven() {
  if [ "${FCM_FORCE_PORTABLE_TOOLS:-0}" != "1" ] && command -v mvn >/dev/null 2>&1; then
    local version; version="$(maven_version "$(command -v mvn)" || true)"
    if maven_is_compatible "$version"; then
      ok "Use system Maven $version."
      return
    fi
    warn "System Maven version '${version:-unknown}' is missing or too old."
  fi
  if [ -x "$TOOLS/maven/bin/mvn" ]; then
    local version; version="$(maven_version "$TOOLS/maven/bin/mvn" || true)"
    maven_is_compatible "$version" || die "Portable Maven is too old or invalid (found '${version:-unknown}'; need Maven 3.6.3 or newer)."
    export PATH="$TOOLS/maven/bin:$PATH"
    ok "Use portable Maven $version: $TOOLS/maven"
    return
  fi
  die "No compatible Maven found. Please run: ./setup.sh"
}

# ---------------------------------------------------------------- validate the project
[ -f pom.xml ] || die "No pom.xml found. Please run this script in the root directory of the project."
use_jdk
use_maven

grep -q "spring-boot-starter-test" pom.xml \
  || die "pom.xml does not contain spring-boot-starter-test. Run ./setup.sh (auto-add) or manually add this dependency."
[ -f "$TEST_FILE" ] \
  || die "No $TEST_FILE found. Please copy FcmFlowTest.java to the correct path."

echo
if [ "$#" -eq 0 ]; then set -- test; fi
say "JDK currently in use: $(java -version 2>&1 | sed -n '1p')"
say "Running: mvn -B $*"
set +e
mvn -B "$@"
code=$?
set -e

echo
if [ "$code" -eq 0 ]; then
  ok "ALL TESTS PASSED."
else
  warn "Some tests failed (exit $code). See details: target/surefire-reports/com.seminar.fcm.FcmFlowTest.txt"
  echo
  say "JDK currently in use: $(java -version 2>&1 | sed -n '1p')"
  say "Root cause (first 'Caused by' lines):"
  { grep -h "Caused by" target/surefire-reports/*.txt 2>/dev/null | awk '!seen[$0]++' | head -6 | cut -c1-400; } || true
  echo
fi
exit "$code"