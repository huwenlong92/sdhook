#!/usr/bin/env sh
set -eu

REPO="${GITHUB_REPO:-huwenlong92/sdhook}"
PREFIX="${PREFIX:-/usr/local}"
VERSION="${VERSION:-latest}"
GITHUB_PROXY="${GITHUB_PROXY:-${SDHOOK_GITHUB_PROXY:-}}"
RELEASE_BASE_URL="${RELEASE_BASE_URL:-${SDHOOK_RELEASE_BASE_URL:-}}"
CURL_CONNECT_TIMEOUT="${CURL_CONNECT_TIMEOUT:-15}"
CURL_RETRY="${CURL_RETRY:-2}"
CURL_RETRY_DELAY="${CURL_RETRY_DELAY:-2}"

INSTALL_SYSTEMD="${INSTALL_SYSTEMD:-0}"
CONFIG="${CONFIG:-/etc/sdhook/config.toml}"
SERVICE_USER="${SERVICE_USER:-sdhook}"
SERVICE_GROUP="${SERVICE_GROUP:-sdhook}"
SERVICE_UID="${SERVICE_UID:-9801}"
SERVICE_GID="${SERVICE_GID:-9801}"
NO_START="${NO_START:-0}"
DATA_DIR="${DATA_DIR:-/var/lib/sdhook}"
LOGS_DIR="${LOGS_DIR:-/var/log/sdhook}"
SYSTEMD_UNIT="${SYSTEMD_UNIT:-/etc/systemd/system/sdhook.service}"
DEPLOY_DIR="${DEPLOY_DIR:-}"
SDHOOK_BIN_PATH="${SDHOOK_BIN_PATH:-}"

need() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

parent_dir() {
  case "$1" in
    */*) printf '%s\n' "${1%/*}" ;;
    *) printf '.\n' ;;
  esac
}

sed_escape() {
  printf '%s' "$1" | sed 's/[|&\\]/\\&/g'
}

github_proxy_url() {
  case "$GITHUB_PROXY" in
    *'{url}'*) printf '%s\n' "$(printf '%s' "$GITHUB_PROXY" | sed "s|{url}|$(sed_escape "$1")|g")" ;;
    *) printf '%s/%s\n' "${GITHUB_PROXY%/}" "$1" ;;
  esac
}

curl_text() {
  url="$1"
  if [ -n "$GITHUB_PROXY" ]; then
    proxy_url="$(github_proxy_url "$url")"
    if curl -fsSL --connect-timeout "$CURL_CONNECT_TIMEOUT" --retry "$CURL_RETRY" --retry-delay "$CURL_RETRY_DELAY" "$proxy_url"; then
      return 0
    fi
    echo "github proxy failed, fallback to ${url}" >&2
  fi
  curl -fsSL --connect-timeout "$CURL_CONNECT_TIMEOUT" --retry "$CURL_RETRY" --retry-delay "$CURL_RETRY_DELAY" "$url"
}

curl_file() {
  url="$1"
  dest="$2"
  if [ -n "$GITHUB_PROXY" ]; then
    proxy_url="$(github_proxy_url "$url")"
    echo "      ${proxy_url}"
    if curl -fL --connect-timeout "$CURL_CONNECT_TIMEOUT" --retry "$CURL_RETRY" --retry-delay "$CURL_RETRY_DELAY" --progress-bar "$proxy_url" -o "$dest"; then
      return 0
    fi
    echo "github proxy failed, fallback to ${url}" >&2
  fi
  echo "      ${url}"
  curl -fL --connect-timeout "$CURL_CONNECT_TIMEOUT" --retry "$CURL_RETRY" --retry-delay "$CURL_RETRY_DELAY" --progress-bar "$url" -o "$dest"
}

release_asset_url() {
  tag="$1"
  asset="$2"
  if [ -n "$RELEASE_BASE_URL" ]; then
    case "$RELEASE_BASE_URL" in
      *'{tag}'*|*'{asset}'*)
        printf '%s\n' "$(printf '%s' "$RELEASE_BASE_URL" | sed -e "s|{tag}|$(sed_escape "$tag")|g" -e "s|{asset}|$(sed_escape "$asset")|g")"
        ;;
      *)
        printf '%s/%s/%s\n' "${RELEASE_BASE_URL%/}" "$tag" "$asset"
        ;;
    esac
  else
    printf 'https://github.com/%s/releases/download/%s/%s\n' "$REPO" "$tag" "$asset"
  fi
}

need install
need sed

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

TMP_DIR="$(mktemp -d)"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

if [ -n "$SDHOOK_BIN_PATH" ]; then
  TAG="${VERSION:-local}"
  if [ "$TAG" = "latest" ]; then
    TAG="local"
  fi
  BIN_PATH="$SDHOOK_BIN_PATH"
  echo "[1/5] Using local binary"
  echo "      $BIN_PATH"
else
  need curl
  need tar

  if [ "$VERSION" = "latest" ]; then
    echo "[1/5] Resolving latest release"
    if [ -n "$RELEASE_BASE_URL" ]; then
      TAG="$(curl_text "${RELEASE_BASE_URL%/}/latest.json" | sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' | head -n 1 || true)"
    fi
    if [ -z "${TAG:-}" ]; then
      TAG="$(curl_text "https://api.github.com/repos/${REPO}/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -n 1)"
    fi
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
  URL="$(release_asset_url "$TAG" "$ASSET")"

  echo "[2/5] Downloading ${ASSET}"
  curl_file "$URL" "$TMP_DIR/$ASSET"
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
fi

BIN_DEST="$PREFIX/bin/sdhook"

echo "[4/5] Installing to ${BIN_DEST}"
install -d "$PREFIX/bin"
install -m 0755 "$BIN_PATH" "$BIN_DEST"

copy_deploy_file() {
  rel_path="$1"
  dest="$2"
  if [ -n "$DEPLOY_DIR" ] && [ -f "$DEPLOY_DIR/$rel_path" ]; then
    cp "$DEPLOY_DIR/$rel_path" "$dest"
    return
  fi
  if [ "${TAG:-local}" = "local" ]; then
    echo "DEPLOY_DIR is required when INSTALL_SYSTEMD=1 with SDHOOK_BIN_PATH" >&2
    exit 1
  fi
  need curl
  curl_file "https://raw.githubusercontent.com/${REPO}/${TAG}/deploy/${rel_path}" "$dest"
}

install_systemd() {
  if [ "$OS" != "linux" ]; then
    echo "INSTALL_SYSTEMD=1 is only supported on Linux" >&2
    exit 1
  fi
  need id
  if [ "$(id -u)" != "0" ]; then
    echo "INSTALL_SYSTEMD=1 must be run as root" >&2
    exit 1
  fi
  need sed
  need systemctl

  config_dir="$(parent_dir "$CONFIG")"
  install -d -m 0755 "$config_dir"
  install -d "$DATA_DIR" "$LOGS_DIR"

  if [ ! -f "$CONFIG" ]; then
    copy_deploy_file "sdhook/config.toml" "$TMP_DIR/config.toml"
    install -m 0640 "$TMP_DIR/config.toml" "$CONFIG"
  fi

  if [ "$SERVICE_UID" != "0" ] || [ "$SERVICE_USER" != "root" ]; then
    need getent
    need groupadd
    need useradd

    group_line="$(getent group "$SERVICE_GROUP" 2>/dev/null || true)"
    if [ -n "$group_line" ]; then
      old_ifs="$IFS"
      IFS=:
      set -- $group_line
      existing_gid="$3"
      IFS="$old_ifs"
      if [ "$existing_gid" != "$SERVICE_GID" ]; then
        echo "group $SERVICE_GROUP already exists with gid $existing_gid, expected $SERVICE_GID" >&2
        exit 1
      fi
    else
      groupadd --system --gid "$SERVICE_GID" "$SERVICE_GROUP"
    fi

    existing_uid="$(id -u "$SERVICE_USER" 2>/dev/null || true)"
    if [ -n "$existing_uid" ]; then
      if [ "$existing_uid" != "$SERVICE_UID" ]; then
        echo "user $SERVICE_USER already exists with uid $existing_uid, expected $SERVICE_UID" >&2
        exit 1
      fi
    else
      useradd --system --uid "$SERVICE_UID" --gid "$SERVICE_GROUP" --home "$DATA_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"
    fi
  fi

  chown "$SERVICE_USER:$SERVICE_GROUP" "$CONFIG"
  chmod 0640 "$CONFIG"
  chown -R "$SERVICE_USER:$SERVICE_GROUP" "$DATA_DIR" "$LOGS_DIR"
  chmod -R 750 "$DATA_DIR" "$LOGS_DIR"

  copy_deploy_file "systemd/sdhook.service.tpl" "$TMP_DIR/sdhook.service.tpl"
  sed \
    -e "s|{{USER}}|$(sed_escape "$SERVICE_USER")|g" \
    -e "s|{{GROUP}}|$(sed_escape "$SERVICE_GROUP")|g" \
    -e "s|{{BIN}}|$(sed_escape "$BIN_DEST")|g" \
    -e "s|{{CONFIG}}|$(sed_escape "$CONFIG")|g" \
    -e "s|{{WORKING_DIR}}|$(sed_escape "$config_dir")|g" \
    "$TMP_DIR/sdhook.service.tpl" \
    > "$TMP_DIR/sdhook.service"
  install -m 0644 "$TMP_DIR/sdhook.service" "$SYSTEMD_UNIT"

  systemctl daemon-reload
  unit_name="${SYSTEMD_UNIT##*/}"
  if [ "$NO_START" = "1" ]; then
    echo "systemd unit installed: $SYSTEMD_UNIT"
    echo "Start later: systemctl enable --now $unit_name"
  else
    systemctl enable "$unit_name"
    if systemctl is-active --quiet "$unit_name"; then
      systemctl restart "$unit_name"
    else
      systemctl start "$unit_name"
    fi
    echo "SDHook systemd service is running."
    echo "View logs: journalctl -u $unit_name -f"
  fi
}

if [ "$INSTALL_SYSTEMD" = "1" ]; then
  echo "[5/5] Installing systemd service"
  install_systemd
else
  echo "[5/5] Installed: $BIN_DEST"
  "$BIN_DEST" --version 2>/dev/null || "$BIN_DEST" --help
fi
