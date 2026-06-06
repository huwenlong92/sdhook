#!/usr/bin/env sh
set -eu

REPO="${GITHUB_REPO:-huwenlong92/sdhook}"
PREFIX="${PREFIX:-/usr/local}"
VERSION="${VERSION:-latest}"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

need curl
need tar

case "$(uname -s)" in
  Darwin) OS="darwin" ;;
  Linux) OS="linux" ;;
  *) echo "unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

case "$(uname -m)" in
  arm64|aarch64) ARCH="arm64" ;;
  x86_64|amd64) ARCH="amd64" ;;
  *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
esac

if [ "$VERSION" = "latest" ]; then
  echo "[1/5] Resolving latest release"
  TAG="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)"
else
  case "$VERSION" in
    v*) TAG="$VERSION" ;;
    *) TAG="v$VERSION" ;;
  esac
  echo "[1/5] Using release ${TAG}"
fi

if [ -z "${TAG:-}" ]; then
  echo "failed to resolve latest release tag" >&2
  exit 1
fi

ASSET="sdhook-${OS}-${ARCH}.tar.gz"
URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"
TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "[2/5] Downloading ${ASSET}"
echo "      ${URL}"
curl -fL --progress-bar "$URL" -o "$TMP_DIR/$ASSET"
echo "[3/5] Extracting archive"
if tar --no-xattrs -xzf "$TMP_DIR/$ASSET" -C "$TMP_DIR" >/dev/null 2>&1; then
  :
else
  tar -xzf "$TMP_DIR/$ASSET" -C "$TMP_DIR"
fi

BIN_PATH="$(find "$TMP_DIR" -type f -name sdhook | head -n 1)"
if [ -z "$BIN_PATH" ]; then
  echo "sdhook binary not found in archive" >&2
  exit 1
fi

echo "[4/5] Installing to ${PREFIX}/bin/sdhook"
install -d "$PREFIX/bin"
install -m 0755 "$BIN_PATH" "$PREFIX/bin/sdhook"

echo "[5/5] Installed: $PREFIX/bin/sdhook"
"$PREFIX/bin/sdhook" --version 2>/dev/null || "$PREFIX/bin/sdhook" --help
