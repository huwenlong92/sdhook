#!/usr/bin/env sh
set -eu

REPO="${GITHUB_REPO:-huwenlong92/sdhook}"
PREFIX="${PREFIX:-/usr/local}"
VERSION="${VERSION:-latest}"
AUTO_UPGRADE="${AUTO_UPGRADE:-${SDHOOK_AGENT_AUTO_UPGRADE:-true}}"
UPGRADE_REPO="${UPGRADE_REPO:-${SDHOOK_AGENT_UPGRADE_REPO:-$REPO}}"

INSTALL_SYSTEMD="${INSTALL_SYSTEMD:-0}"
SERVER="${SERVER:-${SDHOOK_AGENT_SERVER:-}}"
NODE_KEY="${NODE_KEY:-${SDHOOK_AGENT_KEY:-}}"
TOKEN="${TOKEN:-${SDHOOK_AGENT_TOKEN:-}}"
SERVICE_USER="${SERVICE_USER:-root}"
SERVICE_GROUP="${SERVICE_GROUP:-root}"
SERVICE_UID="${SERVICE_UID:-0}"
SERVICE_GID="${SERVICE_GID:-0}"
NO_START="${NO_START:-0}"
DATA_DIR="${DATA_DIR:-/var/lib/sdhook-agent}"
CONFIG="${CONFIG:-${SDHOOK_AGENT_CONFIG:-/etc/sdhook/agent.toml}}"
SYSTEMD_UNIT="${SYSTEMD_UNIT:-/etc/systemd/system/sdhook-agent.service}"
DEPLOY_DIR="${DEPLOY_DIR:-}"
SDHOOK_AGENT_BIN_PATH="${SDHOOK_AGENT_BIN_PATH:-}"

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

toml_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
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

if [ -n "$SDHOOK_AGENT_BIN_PATH" ]; then
  TAG="${VERSION:-local}"
  if [ "$TAG" = "latest" ]; then
    TAG="local"
  fi
  BIN_PATH="$SDHOOK_AGENT_BIN_PATH"
  echo "[1/5] Using local agent binary"
  echo "      $BIN_PATH"
else
  need curl
  need tar

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

  ASSET="sdhook-agent-${OS}-${ARCH}.tar.gz"
  URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"

  echo "[2/5] Downloading ${ASSET}"
  echo "      ${URL}"
  curl -fL --progress-bar "$URL" -o "$TMP_DIR/$ASSET"
  echo "[3/5] Extracting archive"
  if tar --no-xattrs -xzf "$TMP_DIR/$ASSET" -C "$TMP_DIR" >/dev/null 2>&1; then
    :
  else
    tar -xzf "$TMP_DIR/$ASSET" -C "$TMP_DIR"
  fi

  BIN_PATH="$(find "$TMP_DIR" -type f -name sdhook-agent | head -n 1)"
  if [ -z "$BIN_PATH" ]; then
    echo "sdhook-agent binary not found in archive" >&2
    exit 1
  fi
fi

BIN_DIR="$PREFIX/bin"
BIN_DEST="$BIN_DIR/sdhook-agent"

echo "[4/5] Installing to ${BIN_DEST}"
install -d "$BIN_DIR"
BIN_TMP="$BIN_DIR/.sdhook-agent.$$"
install -m 0755 "$BIN_PATH" "$BIN_TMP"
mv -f "$BIN_TMP" "$BIN_DEST"

copy_deploy_file() {
  rel_path="$1"
  dest="$2"
  if [ -n "$DEPLOY_DIR" ] && [ -f "$DEPLOY_DIR/$rel_path" ]; then
    cp "$DEPLOY_DIR/$rel_path" "$dest"
    return
  fi
  if [ "${TAG:-local}" = "local" ]; then
    echo "DEPLOY_DIR is required when INSTALL_SYSTEMD=1 with SDHOOK_AGENT_BIN_PATH" >&2
    exit 1
  fi
  need curl
  curl -fsSL "https://raw.githubusercontent.com/${REPO}/${TAG}/deploy/${rel_path}" -o "$dest"
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
  if [ -z "$SERVER" ] || [ -z "$NODE_KEY" ] || [ -z "$TOKEN" ]; then
    echo "INSTALL_SYSTEMD=1 requires SERVER, NODE_KEY, and TOKEN" >&2
    exit 1
  fi
  need sed
  need systemctl

  config_dir="$(parent_dir "$CONFIG")"
  install -d -m 0755 "$config_dir"
  install -d "$DATA_DIR"

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

  cat > "$TMP_DIR/config.toml" <<TOML
server = "$(toml_escape "$SERVER")"
key = "$(toml_escape "$NODE_KEY")"
token = "$(toml_escape "$TOKEN")"
auto_upgrade = $AUTO_UPGRADE
upgrade_repo = "$(toml_escape "$UPGRADE_REPO")"
TOML
  install -m 0600 "$TMP_DIR/config.toml" "$CONFIG"
  chown "$SERVICE_USER:$SERVICE_GROUP" "$CONFIG"
  chown -R "$SERVICE_USER:$SERVICE_GROUP" "$DATA_DIR"
  chmod 0600 "$CONFIG"
  chmod -R 750 "$DATA_DIR"

  copy_deploy_file "systemd/sdhook-agent.service.tpl" "$TMP_DIR/sdhook-agent.service.tpl"
  sed \
    -e "s|{{USER}}|$(sed_escape "$SERVICE_USER")|g" \
    -e "s|{{GROUP}}|$(sed_escape "$SERVICE_GROUP")|g" \
    -e "s|{{BIN}}|$(sed_escape "$BIN_DEST")|g" \
    -e "s|{{CONFIG}}|$(sed_escape "$CONFIG")|g" \
    -e "s|{{WORKING_DIR}}|$(sed_escape "$DATA_DIR")|g" \
    "$TMP_DIR/sdhook-agent.service.tpl" \
    > "$TMP_DIR/sdhook-agent.service"
  install -m 0644 "$TMP_DIR/sdhook-agent.service" "$SYSTEMD_UNIT"

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
    echo "SDHook agent systemd service is running."
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
