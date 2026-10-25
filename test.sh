#!/usr/bin/env bash
# =============================================================================
#  test.sh  -  macOS / Linux
#  CHI CHAY AUTOTEST (mvn test). Khong cai dat gi ca.
#  Neu chua co JDK/Maven -> bao ban chay ./setup.sh truoc.
#
#  Dung:
#    ./test.sh                              # chay toan bo test
#    ./test.sh -Dtest=FcmFlowTest test      # chi chay file FcmFlowTest
#    ./test.sh -Dtest=FcmFlowTest#fullFlow_registerThenOrderThenSelfCleaning test
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

# ---------------------------------------------------------------- tìm JDK
use_jdk() {
  if command -v java >/dev/null 2>&1 && command -v javac >/dev/null 2>&1; then
    local v; v="$(java_major "$(command -v java)")"
    if [ "${v:-0}" -ge "$MIN_JAVA" ] && [ "${v:-0}" -le "$MAX_JAVA" ]; then ok "Dùng JDK $v của hệ thống."; return; fi
    warn "JDK hệ thống là bản $v (cần $MIN_JAVA-$MAX_JAVA) -> bỏ qua, tìm JDK portable."
  fi
  for cand in "$TOOLS/jdk/Contents/Home" "$TOOLS/jdk"; do
    if [ -x "$cand/bin/javac" ]; then
      export JAVA_HOME="$cand"; export PATH="$JAVA_HOME/bin:$PATH"
      ok "Dùng JDK portable: $cand"; return
    fi
  done
  die "Chưa có JDK $MIN_JAVA-$MAX_JAVA phù hợp. Hãy chạy trước:  ./setup.sh"
}

# ---------------------------------------------------------------- tìm Maven
use_maven() {
  if command -v mvn >/dev/null 2>&1; then ok "Dùng Maven của hệ thống."; return; fi
  if [ -x "$TOOLS/maven/bin/mvn" ]; then
    export PATH="$TOOLS/maven/bin:$PATH"; ok "Dùng Maven portable: $TOOLS/maven"; return
  fi
  die "Chưa có Maven. Hãy chạy trước:  ./setup.sh"
}

# ---------------------------------------------------------------- kiểm tra project
[ -f pom.xml ] || die "Không thấy pom.xml. Hãy chạy script này ở thư mục gốc của project."
use_jdk
use_maven

grep -q "spring-boot-starter-test" pom.xml \
  || die "pom.xml chưa có spring-boot-starter-test. Chạy ./setup.sh (tự thêm) hoặc thêm tay dependency này."
[ -f "$TEST_FILE" ] \
  || die "Chưa thấy $TEST_FILE. Hãy chép FcmFlowTest.java vào đúng đường dẫn đó."

echo
if [ "$#" -eq 0 ]; then set -- test; fi
say "JDK đang dùng: $(java -version 2>&1 | head -1)"
say "Chạy: mvn -B $*"
set +e
mvn -B "$@"
code=$?
set -e

echo
if [ "$code" -eq 0 ]; then
  ok "TẤT CẢ TEST PASS."
else
  warn "Có test lỗi (exit $code). Xem chi tiết: target/surefire-reports/com.seminar.fcm.FcmFlowTest.txt"
  echo
  say "JDK đã dùng: $(java -version 2>&1 | head -1)"
  say "Nguyên nhân gốc (các dòng 'Caused by' đầu tiên):"
  { grep -h "Caused by" target/surefire-reports/*.txt 2>/dev/null | awk '!seen[$0]++' | head -6 | cut -c1-400; } || true
  echo
fi
exit "$code"
