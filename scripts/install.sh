#!/usr/bin/env sh
# install.sh — Cloudsmith CLI installer (standalone binary, PUBLIC repo only).
# Detects host -> resolves the matching tagged archive -> downloads + extracts the
# onedir bundle -> puts `cloudsmith` on PATH -> authenticates with available creds.
# NO pip. NO zipapp. Everything is pulled from a public Cloudsmith repository.
#
# Release layout:
#   package name : cloudsmith-cli-<target>
#   filename     : cloudsmith-<version>-<target>.tar.gz   (.zip on windows)
#   archive body : cloudsmith/cloudsmith  (+ _internal/)  <- keep the dir together
#   tags         : standalone-binary, <os>, <arch>, <libc?>, <target>
set -eu

REPO="bart-demo-org-terraform/cli-binary-release-test"   # OWNER/REPOSITORY (public)
VERSION="latest"                                          # e.g. 1.19.0, or 'latest'
INSTALL_ROOT="${INSTALL_ROOT:-$HOME/.cloudsmith}"
DO_AUTH="1"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)         REPO="$2";         shift 2 ;;
    --version)      VERSION="$2";      shift 2 ;;
    --install-root) INSTALL_ROOT="$2"; shift 2 ;;
    --no-auth)      DO_AUTH="0";       shift ;;
    *) echo "install.sh: unknown arg: $1" >&2; exit 1 ;;
  esac
done

# 1) Detect host -> target triple (matches the release matrix exactly).
OS="$(uname -s)"; RAW_ARCH="$(uname -m)"; LIBC=""
case "$OS" in
  Darwin)
    OS="macos"
    case "$RAW_ARCH" in
      arm64|aarch64) ARCH="arm64" ;;
      x86_64|amd64)  ARCH="x86_64" ;;
      *) echo "install.sh: unsupported macOS arch: $RAW_ARCH" >&2; exit 1 ;;
    esac
    TARGET="${OS}-${ARCH}"
    ;;
  Linux)
    OS="linux"
    case "$RAW_ARCH" in
      x86_64|amd64)  ARCH="x86_64" ;;
      aarch64|arm64) ARCH="aarch64" ;;
      *) echo "install.sh: unsupported Linux arch: $RAW_ARCH" >&2; exit 1 ;;
    esac
    if [ -f /etc/alpine-release ] || ldd /bin/ls 2>&1 | grep -qi musl; then LIBC="musl"; else LIBC="gnu"; fi
    TARGET="${OS}-${ARCH}-${LIBC}"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    OS="windows"; ARCH="x86_64"; TARGET="windows-x86_64"
    ;;
  *) echo "install.sh: unsupported OS: $OS" >&2; exit 1 ;;
esac

EXT=".tar.gz"; [ "$OS" = "windows" ] && EXT=".zip"
NAME="cloudsmith-cli-${TARGET}"
echo "install.sh: host ${TARGET}"

# 2) Resolve the concrete version. Pinned = deterministic. 'latest' = tag query (public).
if [ "$VERSION" = "latest" ] || [ -z "$VERSION" ]; then
  Q="tag:standalone-binary%20tag:${OS}%20tag:${ARCH}"
  [ -n "$LIBC" ] && Q="${Q}%20tag:${LIBC}"
  API="https://api.cloudsmith.io/v1/packages/${REPO}/?query=${Q}&page_size=1&sort=-version"
  RESP="$(curl -fsSL "$API")"
  # The packages API returns a top-level JSON array of packages.
  if command -v jq >/dev/null 2>&1; then
    VERSION="$(printf '%s' "$RESP" | jq -r '.[0].version // empty')"
  elif command -v python3 >/dev/null 2>&1; then
    VERSION="$(printf '%s' "$RESP" | python3 -c 'import sys,json;d=json.load(sys.stdin);d=d if isinstance(d,list) else d.get("data",[]);print(d[0].get("version","") if d else "")')"
  else
    echo "install.sh: need jq or python3 to resolve 'latest'; pass --version instead" >&2; exit 1
  fi
  [ -n "$VERSION" ] || { echo "install.sh: could not resolve latest version for ${TARGET}" >&2; exit 1; }
  echo "install.sh: resolved latest -> ${VERSION}"
fi

FILE="cloudsmith-${VERSION}-${TARGET}${EXT}"
URL="https://dl.cloudsmith.io/public/${REPO}/raw/names/${NAME}/versions/${VERSION}/${FILE}"
echo "install.sh: downloading ${URL}"

# 3) Download + extract the onedir bundle (yields ${INSTALL_ROOT}/cloudsmith/).
mkdir -p "$INSTALL_ROOT"
TMP="$(mktemp -d)"
curl -fsSL --retry 3 -o "${TMP}/${FILE}" "$URL"
case "$FILE" in
  *.zip)    command -v unzip >/dev/null 2>&1 || { echo "install.sh: unzip required for .zip" >&2; exit 1; }
            unzip -o "${TMP}/${FILE}" -d "$INSTALL_ROOT" >/dev/null ;;
  *.tar.gz) tar -xzf "${TMP}/${FILE}" -C "$INSTALL_ROOT" ;;
esac
rm -rf "$TMP"

BIN_DIR="${INSTALL_ROOT}/cloudsmith"
BIN="${BIN_DIR}/cloudsmith"; [ "$OS" = "windows" ] && BIN="${BIN}.exe"
[ -x "$BIN" ] || chmod +x "$BIN"
[ -n "${GITHUB_PATH:-}" ] && echo "$BIN_DIR" >> "$GITHUB_PATH"
export PATH="${BIN_DIR}:$PATH"

"$BIN" --version
echo "install.sh: installed to ${BIN_DIR}"
[ -n "${GITHUB_PATH:-}" ] || echo "install.sh: add to PATH ->  export PATH=\"${BIN_DIR}:\$PATH\""

# 4) Authenticate with whatever credentials are available (API key env, or native
#    OIDC via CLOUDSMITH_ORG + CLOUDSMITH_SERVICE_SLUG with id-token granted in CI).
if [ "$DO_AUTH" = "1" ]; then
  if "$BIN" whoami; then echo "install.sh: authenticated"; else
    echo "install.sh: no usable credentials (CLI installed, not authenticated)" >&2
  fi
fi
