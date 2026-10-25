#!/usr/bin/env bash
# =============================================================================
#  setup.sh  -  macOS / Linux
#  CHI CAI MOI TRUONG (JDK 17+, Maven). Cai nao may co roi thi BO QUA.
#  Cai nao thieu thi tai ban portable vao ./.tools (khong can sudo).
#  Sau khi cai xong, chay test bang:  ./test.sh
# =============================================================================
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

# ---------------------------------------------------------------- tiện ích
download() { # download <url> <file>
  if command -v curl >/dev/null 2>&1; then
    curl -fL --retry 3 --progress-bar "$1" -o "$2"
  elif command -v wget >/dev/null 2>&1; then
    wget -q --show-progress "$1" -O "$2"
  else
    die "Cần 'curl' hoặc 'wget' để tải file. Hãy cài một trong hai (vd: sudo apt install curl)."
  fi
}

download_any() { # download_any <file> <url1> <url2> ...  (thử lần lượt các nguồn)
  local file="$1"; shift
  local u
  for u in "$@"; do
    say "Thử tải: $u"
    if download "$u" "$file"; then return 0; fi
    warn "Thất bại: $u"
    rm -f "$file"
  done
  die "Không tải được từ nguồn nào. Kiểm tra mạng / VPN / proxy / firewall."
}

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "Thiếu lệnh '$1'. Hãy cài nó trước (vd: sudo apt install $1)."; }

java_major() { # in ra major version của java executable $1 (0 nếu lỗi)
  local out
  out="$("$1" -version 2>&1 | awk -F'"' '/version/ {print $2; exit}')" || true
  [ -z "$out" ] && { echo 0; return; }
  case "$out" in
    1.*) echo "$out" | cut -d. -f2 ;;
    *)   echo "$out" | cut -d. -f1 | sed 's/[^0-9].*//' ;;
  esac
}

# ---------------------------------------------------------------- nhận diện OS / CPU
case "$(uname -s)" in
  Linux*)  ADOPT_OS="linux"; [ -f /etc/alpine-release ] && ADOPT_OS="alpine-linux" ;;
  Darwin*) ADOPT_OS="mac" ;;
  *) die "Hệ điều hành '$(uname -s)' không hỗ trợ bằng script .sh. Trên Windows hãy chạy setup-and-test.bat" ;;
esac
case "$(uname -m)" in
  x86_64|amd64)  ADOPT_ARCH="x64" ;;
  arm64|aarch64) ADOPT_ARCH="aarch64" ;;
  *) die "Kiến trúc CPU '$(uname -m)' chưa được hỗ trợ." ;;
esac

# ---------------------------------------------------------------- 1) JDK
ensure_jdk() {
  # a) JDK có sẵn trên máy (cần cả java lẫn javac)
  if command -v java >/dev/null 2>&1 && command -v javac >/dev/null 2>&1; then
    local v; v="$(java_major "$(command -v java)")"
    if [ "${v:-0}" -ge "$MIN_JAVA" ]; then
      ok "Đã có JDK $v trên máy -> bỏ qua cài đặt."
      return
    fi
    warn "JDK trên máy là bản $v (< $MIN_JAVA) -> sẽ dùng bản portable."
  fi

  # b) JDK portable đã tải trước đó
  local home=""
  for cand in "$JDK_DIR/Contents/Home" "$JDK_DIR"; do
    [ -x "$cand/bin/javac" ] && home="$cand" && break
  done

  # c) chưa có -> tải về
  if [ -z "$home" ]; then
    need_cmd tar
    say "Tải JDK $JDK_VERSION (Temurin, $ADOPT_OS/$ADOPT_ARCH) ..."
    mkdir -p "$TOOLS"
    local archive="$TOOLS/jdk.tar.gz"
    download "https://api.adoptium.net/v3/binary/latest/${JDK_VERSION}/ga/${ADOPT_OS}/${ADOPT_ARCH}/jdk/hotspot/normal/eclipse" "$archive"
    rm -rf "$JDK_DIR"; mkdir -p "$JDK_DIR"
    tar -xzf "$archive" -C "$JDK_DIR" --strip-components=1
    rm -f "$archive"
    for cand in "$JDK_DIR/Contents/Home" "$JDK_DIR"; do
      [ -x "$cand/bin/javac" ] && home="$cand" && break
    done
    [ -n "$home" ] || die "Giải nén JDK xong nhưng không tìm thấy bin/javac."
    ok "Đã cài JDK portable tại $home"
  else
    ok "Dùng JDK portable có sẵn tại $home"
  fi

  export JAVA_HOME="$home"
  export PATH="$JAVA_HOME/bin:$PATH"
}

# ---------------------------------------------------------------- 2) Maven
ensure_maven() {
  if command -v mvn >/dev/null 2>&1; then
    ok "Đã có Maven trên máy -> bỏ qua cài đặt."
    return
  fi
  if [ ! -x "$MVN_DIR/bin/mvn" ]; then
    need_cmd tar
    say "Tải Maven $MAVEN_VERSION ..."
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
    ok "Đã cài Maven portable tại $MVN_DIR"
  else
    ok "Dùng Maven portable có sẵn tại $MVN_DIR"
  fi
  export PATH="$MVN_DIR/bin:$PATH"
}

# ---------------------------------------------------------------- 3) Kiểm tra project
ensure_project() {
  [ -f pom.xml ] || die "Không thấy pom.xml. Hãy chạy script này ở thư mục gốc của project."

  if ! grep -q "spring-boot-starter-test" pom.xml; then
    say "pom.xml chưa có spring-boot-starter-test -> tự thêm vào."
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
    ok "Đã thêm dependency (bản gốc lưu ở pom.xml.bak)."
  fi

  [ -f "$TEST_FILE" ] || warn "Chưa thấy $TEST_FILE — hãy chép FcmFlowTest.java vào đó trước khi chạy test."

  # tránh commit nhầm thư mục tải về
  if [ -f .gitignore ] && ! grep -qxF ".tools/" .gitignore; then
    printf '\n# công cụ portable do setup-and-test tải về\n.tools/\n' >> .gitignore
  fi
}

# ---------------------------------------------------------------- main
say "Hệ điều hành: $ADOPT_OS / $ADOPT_ARCH"
ensure_jdk
ensure_maven
ensure_project

echo
java -version 2>&1 | head -1
mvn -v 2>&1 | head -1
echo
ok "Cài môi trường xong. Giờ chạy test bằng: ./test.sh"
