#!/usr/bin/env bash
# test.sh - macOS / Linux. Runs the autotests only (mvn test). Run ./setup.sh first if JDK/Maven are missing.
# Usage:
#   ./test.sh                              # run all tests
#   ./test.sh -Dtest=FcmFlowTest test      # run only FcmFlowTest
set -euo pipefail

cd "$(dirname "$0")"
ROOT="$(pwd)"
TOOLS="$ROOT/.tools"
MIN_JAVA=17
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

use_jdk() {
  if command -v java >/dev/null 2>&1 && command -v javac >/dev/null 2>&1; then
    local v; v="$(java_major "$(command -v java)")"
    if [ "${v:-0}" -ge "$MIN_JAVA" ]; then ok "Using system JDK $v."; return; fi
  fi
  for cand in "$TOOLS/jdk/Contents/Home" "$TOOLS/jdk"; do
    if [ -x "$cand/bin/javac" ]; then
      export JAVA_HOME="$cand"; export PATH="$JAVA_HOME/bin:$PATH"
      ok "Using portable JDK: $cand"; return
    fi
  done
  die "JDK $MIN_JAVA+ not found. Run first:  ./setup.sh"
}

use_maven() {
  if command -v mvn >/dev/null 2>&1; then ok "Using system Maven."; return; fi
  if [ -x "$TOOLS/maven/bin/mvn" ]; then
    export PATH="$TOOLS/maven/bin:$PATH"; ok "Using portable Maven: $TOOLS/maven"; return
  fi
  die "Maven not found. Run first:  ./setup.sh"
}

[ -f pom.xml ] || die "pom.xml not found. Run this script from the project root."
use_jdk
use_maven

grep -q "spring-boot-starter-test" pom.xml \
  || die "pom.xml has no spring-boot-starter-test. Run ./setup.sh (adds it) or add the dependency manually."
[ -f "$TEST_FILE" ] \
  || die "$TEST_FILE not found. Copy FcmFlowTest.java to that path."

echo
if [ "$#" -eq 0 ]; then set -- test; fi
say "Running: mvn -B $*"
set +e
mvn -B "$@"
code=$?
set -e

echo
if [ "$code" -eq 0 ]; then
  ok "ALL TESTS PASSED."
else
  warn "Some tests failed (exit $code). Details: target/surefire-reports/com.seminar.fcm.FcmFlowTest.txt"
fi
exit "$code"
