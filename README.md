# SDHook

SDHook is a lightweight webhook deployment tool with a built-in Web UI.

It runs as a single binary and manages automatic deployments for multiple projects from GitHub, Gitee, Gitea, GitLab, Harbor, or a generic webhook endpoint.

## Install

Install the latest binary:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | sh
```

Install a specific version:

```bash
VERSION=0.1.0 curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | sh
```

Install to a custom prefix:

```bash
PREFIX=$HOME/.local curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | sh
```

## Quick Start

Run:

```bash
sdhook
```

Open:

```text
http://127.0.0.1:9000
```

Default login:

```text
admin / admin
```

Default runtime paths:

```text
~/.sdhook/
├── config.toml   # optional; defaults are used when it is missing
├── sdhook.db
└── logs/
    └── example/
        └── deploy.log
```

## Config

Use a custom config file:

```bash
sdhook --config /etc/sdhook/config.toml
```

or:

```bash
SDHOOK_CONFIG=/etc/sdhook/config.toml sdhook
```

Main config:

```toml
# HTTP service port.
port = 9000

# Production deployment log directory.
logs_dir = "/var/log/sdhook"

[database]
# Database driver. SQLite is currently supported.
driver = "sqlite"

# SQLite database file.
# Can be overridden with --db-path.
path = "/var/lib/sdhook/sdhook.db"

# Reserved Postgres connection URL.
# Can be overridden with --db-url.
# url = "postgres://sdhook:password@127.0.0.1:5432/sdhook"
```

Users, project configuration, and deployment summary records are stored in the SQLite database configured by `database.path`. On first install, SDHook creates the default `admin / admin` account when the users table is empty.

Detailed deployment logs stay on disk to keep SQLite small:

```text
/var/log/sdhook/<project>/deploy.log
```

## Nodes And Agent

The main SDHook instance can manage multiple deployment nodes. Other servers run the same binary in agent mode and connect back to the main instance over HTTPS long polling.

Create a node in the Web UI under Nodes. The node `key` is the stable agent identity and project target value; `name` is for display. Each node has its own token; the token is shown only when the node is created or reset:

```bash
sdhook-agent --server https://sdhook.example.com --key server-a --token xxx
```

The agent has its own binary and installer:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install-agent.sh | \
  sudo env INSTALL_SYSTEMD=1 SERVER=https://sdhook.example.com NODE_KEY=server-a TOKEN=xxx sh
```

With `INSTALL_SYSTEMD=1`, `install-agent.sh` writes `/etc/sdhook-agent/agent.env`, renders `/etc/systemd/system/sdhook-agent.service`, runs `systemctl daemon-reload`, enables the unit, and starts it. If the unit is already active, the installer restarts it so an upgraded agent binary takes effect.

On startup, the agent sends an initial heartbeat. If the first connection never succeeds, the process exits so installation or token problems are visible immediately. After the agent has connected once, it keeps retrying heartbeat, long polling, and final job status reporting when the main SDHook instance is down, restarting, or temporarily unreachable.

Resetting a node token in the main UI invalidates the old token immediately. A running agent using the old token exits on authentication failure instead of retrying forever. Update the token in the agent command or `/etc/sdhook-agent/agent.env`, then restart the agent service. The systemd unit uses `Restart=always` and `RestartSec=5` for process crashes, but token resets still require updating the saved token.

Projects with no selected nodes run on the main SDHook host. Projects with selected nodes are queued for those agents. When a node has `work_dir` configured, the agent runs the project at `<work_dir>/<project_key>`; otherwise it uses the project path. Deploy records store `node_id` and display the node key/name through the nodes table.

The node page shows local interface IPs reported by the agent and the remote source address observed by the main SDHook server. Behind a reverse proxy, preserve `X-Forwarded-For` or `X-Real-IP` to keep the source address useful.

## Webhook URLs

Project `example`:

```text
GitHub:  POST http://server:9000/hook/github/example
Gitee:   POST http://server:9000/hook/gitee/example
Gitea:   POST http://server:9000/hook/gitea/example
GitLab:  POST http://server:9000/hook/gitlab/example
Harbor:  POST http://server:9000/hook/harbor/example
Generic: POST http://server:9000/hook/generic/example?token=example-deploy-token
```

The Web UI provides copy buttons for webhook URLs.

Repository hooks support branch and tag filters:

```json
{
  "branch": "main|release/*",
  "tag": "v*|latest"
}
```

Each project has exactly one `hook` and stores its own `webhook_secret`.

For GitHub, project `webhook_secret` verifies `X-Hub-Signature-256`.

For Gitee, project `webhook_secret` verifies `X-Gitee-Token`.

For Gitea, project `webhook_secret` verifies `X-Gitea-Signature` or `X-Gogs-Signature`.

For GitLab, project `webhook_secret` verifies `X-Gitlab-Token`.

For Harbor, project `webhook_secret` must match the `Authorization` header exactly.

Harbor supports image-level filtering with regex:

```json
{
  "repository_pattern": "^library/api$",
  "tag_pattern": "^latest$"
}
```

## systemd

`sdhook` and `sdhook start` both start the web service. Startup logs are written to stdout. When running under systemd, read startup and runtime logs from journal.

Create config files and install the systemd service:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | sudo env INSTALL_SYSTEMD=1 sh
```

This command creates `/etc/sdhook/config.toml`, `/var/lib/sdhook/sdhook.db`, `/var/log/sdhook`, the default admin user, the `sdhook` system user with UID/GID `9801`, and `/etc/systemd/system/sdhook.service`. It also runs `systemctl daemon-reload`, enables the unit, and starts it. If the unit is already active, the installer restarts it so an upgraded binary takes effect.

Create files and the unit without starting the service:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | sudo env INSTALL_SYSTEMD=1 NO_START=1 sh
```

Use a custom config or install prefix:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | sudo env INSTALL_SYSTEMD=1 CONFIG=/etc/sdhook/config.toml PREFIX=/usr/local sh
```

Run the service as root:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | sudo env INSTALL_SYSTEMD=1 SERVICE_USER=root SERVICE_GROUP=root SERVICE_UID=0 SERVICE_GID=0 sh
```

Root mode is useful when deployment commands need direct access to `docker compose`, project directories, or system services. Be careful: webhook-triggered commands will also run as root.

Older installs may still have a systemd unit that points to `/etc/sdhook/config.json`. Rerun the current installer with `INSTALL_SYSTEMD=1` to render the current unit using `/etc/sdhook/config.toml`. Existing `config.toml` files are kept; if the file does not exist, the installer creates the default one. Back up the old config and database before upgrading.

SDHook rejects clearly dangerous deployment commands before saving config and before running deploys, including recursive deletion of system paths, `mkfs`, `dd of=/dev/...`, reboot/shutdown commands, `curl`, `wget`, and `docker system prune -af`.

The installer command may still use `curl ... | sh` because it is run manually by the operator. The restriction only applies to project deployment commands.

If deployment needs a remote script, download and review it manually first, then execute the local script from SDHook:

```bash
install -d /etc/sdhook/projects/blog
install -m 0700 deploy.sh /etc/sdhook/projects/blog/deploy.sh
```

Configure this command in SDHook:

```bash
bash /etc/sdhook/projects/blog/deploy.sh
```

This is a guard against mistakes, not a full shell sandbox. In root mode, only configure trusted webhooks, trusted branch/tag filters, and trusted deployment commands.

If an older install created `uid=999(sdhook)`, it can collide with common container UIDs and make Postgres/Redis processes appear as `sdhook` in `ps`. Migrate it manually:

```bash
sudo systemctl stop sdhook
sudo userdel sdhook
sudo groupdel sdhook 2>/dev/null || true
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | sudo env INSTALL_SYSTEMD=1 SERVICE_UID=9801 SERVICE_GID=9801 sh
```

Or migrate to root mode:

```bash
sudo systemctl stop sdhook
sudo userdel sdhook
sudo groupdel sdhook 2>/dev/null || true
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | sudo env INSTALL_SYSTEMD=1 SERVICE_USER=root SERVICE_GROUP=root SERVICE_UID=0 SERVICE_GID=0 sh
```

Check:

```bash
id sdhook
```

Expected:

```text
uid=9801(sdhook) gid=9801(sdhook) groups=9801(sdhook)
```

Example unit:

```ini
[Unit]
Description=SDHook webhook deployment service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=sdhook
Group=sdhook
ExecStart=/usr/local/bin/sdhook --config /etc/sdhook/config.toml
Restart=always
RestartSec=3
WorkingDirectory=/etc/sdhook

[Install]
WantedBy=multi-user.target
```

The installer and deb package use these deploy templates:

```text
deploy/sdhook/config.toml
deploy/systemd/sdhook.service.tpl
```

These files are not embedded into the `sdhook` binary. The installer reads them from the release tag and renders the systemd unit.

Common commands:

```bash
systemctl daemon-reload
systemctl enable --now sdhook
systemctl status sdhook
systemctl restart sdhook
systemctl stop sdhook
```

View service logs:

```bash
journalctl -u sdhook -f
journalctl -u sdhook --since "1 hour ago"
```

Deployment logs are stored under `logs/<project>/deploy.log` and are also available in the Web UI project detail page.

## Nginx Reverse Proxy

SDHook listens on `127.0.0.1:9000` or `0.0.0.0:9000` by default. Use Nginx if you want to serve it with a domain name and HTTPS.

Example `/etc/nginx/conf.d/sdhook.example.com.conf`:

```nginx
# Redirect HTTP to HTTPS
server {
    listen 80;
    server_name sdhook.example.com;
    return 301 https://$host$request_uri;
}

# SDHook
server {
    listen 443 ssl;
    http2 on;
    server_name sdhook.example.com;

    client_max_body_size 20m;

    ssl_certificate     /etc/nginx/ssl/cf.pem;
    ssl_certificate_key /etc/nginx/ssl/cf.key;

    ssl_protocols TLSv1.2 TLSv1.3;

    access_log /var/log/nginx/sdhook.example.com.access.log;
    error_log  /var/log/nginx/sdhook.example.com.error.log warn;

    location / {
        proxy_pass http://127.0.0.1:9000;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;

        proxy_connect_timeout 60s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;

        proxy_buffering off;
        proxy_redirect off;
    }
}
```

Check and reload Nginx:

```bash
nginx -t
systemctl reload nginx
```

Replace these values:

- `sdhook.example.com`: your domain name.
- `/etc/nginx/ssl/cf.pem` and `/etc/nginx/ssl/cf.key`: your certificate files.
- `http://127.0.0.1:9000`: your SDHook listen address and port.

## Upgrade

For systemd installs, upgrade by rerunning the installer. It downloads the release asset, updates `/usr/local/bin/sdhook`, keeps the existing `/etc/sdhook/config.toml` and `/var/lib/sdhook/sdhook.db`, regenerates the unit, and restarts the service if it is already running.

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | \
  sudo env INSTALL_SYSTEMD=1 VERSION=0.1.1 sh
```

If the service runs as root, keep the same service user settings during upgrade:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | \
  sudo env INSTALL_SYSTEMD=1 VERSION=0.1.1 SERVICE_USER=root SERVICE_GROUP=root SERVICE_UID=0 SERVICE_GID=0 sh
```

Upgrade each agent separately:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install-agent.sh | \
  sudo env INSTALL_SYSTEMD=1 VERSION=0.1.1 SERVER=https://sdhook.example.com NODE_KEY=server-a TOKEN=xxx sh
```

The agent upgrade command rewrites `/etc/sdhook-agent/agent.env` with the provided connection settings and restarts the active `sdhook-agent` unit.

For binary-only installs without systemd, `sdhook upgrade` is still available:

```bash
sdhook upgrade 0.1.1
```

## Releases

Download binaries from:

```text
https://github.com/huwenlong92/sdhook/releases
```
