# SDHook

SDHook is a lightweight webhook deployment tool with a built-in Web UI. It runs as a single server binary and can deploy projects on the main host or on remote agent nodes.

Supported webhook sources:

- GitHub
- Gitee
- Gitea
- GitLab
- Harbor
- Generic webhook

## Features

- Built-in Web UI.
- SQLite by default.
- Project groups, project targets, deploy records, rollback records, and node records.
- Manual deploy and webhook-triggered deploy.
- Git branch/tag deploy target support.
- Docker image version probing for Docker Compose projects.
- Multi-node deploy through the standalone `sdhook-agent` binary.
- Realtime deploy and rollback progress through SSE.
- systemd install scripts for both server and agent.

## Install Server

Install the latest server binary:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | sh
```

Install a specific version:

```bash
VERSION=0.1.13 curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | sh
```

Install as a systemd service:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | \
  sudo env INSTALL_SYSTEMD=1 sh
```

Install as a root-run systemd service:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | \
  sudo env INSTALL_SYSTEMD=1 SERVICE_USER=root SERVICE_GROUP=root SERVICE_UID=0 SERVICE_GID=0 sh
```

Root mode is useful when deploy commands need direct access to `docker compose`, project directories, or system services. Only configure trusted webhooks and trusted deploy commands in root mode.

With `INSTALL_SYSTEMD=1`, the installer:

- installs `/usr/local/bin/sdhook`;
- creates `/etc/sdhook/config.toml` if it does not exist;
- creates `/var/lib/sdhook` and `/var/log/sdhook`;
- renders `/etc/systemd/system/sdhook.service`;
- runs `systemctl daemon-reload`;
- starts the service, or restarts it if it is already active.

Existing `/etc/sdhook/config.toml` and `/var/lib/sdhook/sdhook.db` are kept.

## Install Agent

Create a node in the Web UI first. The node `key` and token are required by the agent.

Run an agent manually:

```bash
sdhook-agent --server https://sdhook.example.com --key server-a --token xxx
```

Install the agent as a systemd service:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install-agent.sh | \
  sudo env INSTALL_SYSTEMD=1 SERVER=https://sdhook.example.com NODE_KEY=server-a TOKEN=xxx sh
```

Install a specific agent version:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install-agent.sh | \
  sudo env INSTALL_SYSTEMD=1 VERSION=0.1.13 SERVER=https://sdhook.example.com NODE_KEY=server-a TOKEN=xxx sh
```

Install only the agent binary without systemd:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install-agent.sh | sh
```

With `INSTALL_SYSTEMD=1`, `install-agent.sh`:

- installs `/usr/local/bin/sdhook-agent`;
- writes `/etc/sdhook/agent.toml`;
- renders `/etc/systemd/system/sdhook-agent.service`;
- runs `systemctl daemon-reload`;
- starts the service, or restarts it if it is already active.

Generated agent config:

```toml
server = "https://sdhook.example.com"
key = "server-a"
token = "xxx"
auto_upgrade = true
upgrade_repo = "huwenlong92/sdhook"
# Optional GitHub acceleration proxy. SDHook falls back to original GitHub URLs if it fails.
github_proxy = "https://gh-proxy.example.com/"
# Optional release mirror. Default asset path is {base}/{tag}/{asset}.
release_base_url = "https://cdn.example.com/sdhook/releases"
```

Agent auto-upgrade starts after the installed agent version includes this capability. Older agents do not understand heartbeat version sync, so upgrade them once with `install-agent.sh`; after that, they follow the main SDHook server version during idle heartbeat windows.

For servers with unstable GitHub access, use the installed SDHook server to serve the installer script and pass a proxy or mirror:

```bash
curl -fsSL https://sdhook.example.com/scripts/install-agent.sh | \
  sudo env INSTALL_SYSTEMD=1 \
  SERVER=https://sdhook.example.com \
  NODE_KEY=server-a \
  TOKEN=xxx \
  GITHUB_PROXY=https://gh-proxy.example.com/ \
  sh
```

`GITHUB_PROXY` supports both `https://proxy.example.com/` and `https://proxy.example.com/{url}` formats. `RELEASE_BASE_URL` / `SDHOOK_AGENT_RELEASE_BASE_URL` can point to an OSS, CDN, or private mirror; it supports `{tag}` and `{asset}` placeholders.

Manual agent upgrade:

```bash
sdhook-agent upgrade
sdhook-agent upgrade 0.1.16
```

Check the agent:

```bash
systemctl status sdhook-agent
journalctl -u sdhook-agent -f
```

## Quick Start

Open the Web UI:

```text
http://127.0.0.1:9000
```

Default login:

```text
admin / admin
```

Change the password after first login.

Default local runtime paths:

```text
~/.sdhook/
├── config.toml
├── sdhook.db
└── logs/
```

Recommended systemd paths:

```text
/etc/sdhook/config.toml
/var/lib/sdhook/sdhook.db
/var/log/sdhook
```

## Upgrade Server

For systemd installs, upgrade by rerunning the installer:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | \
  sudo env INSTALL_SYSTEMD=1 VERSION=0.1.13 sh
```

If the service runs as root, keep the same service settings:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | \
  sudo env INSTALL_SYSTEMD=1 VERSION=0.1.13 SERVICE_USER=root SERVICE_GROUP=root SERVICE_UID=0 SERVICE_GID=0 sh
```

The installer updates the binary, regenerates the systemd unit, and restarts the active service.

Older installs may still point to `/etc/sdhook/config.json`. Rerun the current installer with `INSTALL_SYSTEMD=1` to overwrite the old unit and switch it to `/etc/sdhook/config.toml`.

Back up old files before upgrading from old installs:

```bash
sudo mkdir -p /root/sdhook-backup
sudo cp /etc/sdhook/config.json /root/sdhook-backup/config.json.bak 2>/dev/null || true
sudo cp /etc/sdhook/config.toml /root/sdhook-backup/config.toml.bak 2>/dev/null || true
sudo cp /etc/systemd/system/sdhook.service /root/sdhook-backup/sdhook.service.bak 2>/dev/null || true
sudo cp /var/lib/sdhook/sdhook.db /root/sdhook-backup/sdhook.db.bak 2>/dev/null || true
```

Check the service:

```bash
systemctl status sdhook
journalctl -u sdhook -f
systemctl cat sdhook
```

The current unit should contain:

```text
ExecStart=/usr/local/bin/sdhook --config /etc/sdhook/config.toml
```

For binary-only installs without systemd:

```bash
sdhook upgrade 0.1.13
```

## Upgrade Agent

Upgrade each agent node separately:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install-agent.sh | \
  sudo env INSTALL_SYSTEMD=1 VERSION=0.1.13 SERVER=https://sdhook.example.com NODE_KEY=server-a TOKEN=xxx sh
```

The command updates `/usr/local/bin/sdhook-agent`, rewrites `/etc/sdhook/agent.toml`, regenerates `sdhook-agent.service`, and restarts the active agent service.

If the node token was reset in the Web UI, use the new token in `TOKEN=...`.

## Config

Example production config:

```toml
port = 9000
logs_dir = "/var/log/sdhook"

[database]
driver = "sqlite"
path = "/var/lib/sdhook/sdhook.db"
```

Override config at startup:

```bash
sdhook --config /etc/sdhook/config.toml
SDHOOK_CONFIG=/etc/sdhook/config.toml sdhook
sdhook --config /etc/sdhook/config.toml --port 9000 --logs-dir /var/log/sdhook
sdhook --config /etc/sdhook/config.toml --db-driver sqlite --db-path /var/lib/sdhook/sdhook.db
```

Users, projects, nodes, deploy runs, deploy target records, rollback records, and rollback config are stored in SQLite.

Detailed deploy logs stay on disk:

```text
/var/log/sdhook/<project>/deploy.log
```

## Agent Nodes

Remote machines run the standalone `sdhook-agent` binary. The agent connects back to the main SDHook server over HTTPS long polling, so the main server does not need SSH keys or inbound access to remote nodes.

Create a node in the Web UI under **Nodes**. The node `key` is stable identity, `name` is display text, and each node has its own token. The token is shown only when the node is created or reset.

Agent connection behavior:

- The first startup must successfully send an initial heartbeat. If it cannot connect, the process exits so installation errors are visible.
- After the first successful connection, the agent retries heartbeat, long polling, and final job reporting when the server is down, restarting, or temporarily unreachable.
- If the node token is reset or invalid, the agent exits on authentication failure. Update `/etc/sdhook/agent.toml`, then restart the service.

Projects with no selected nodes run on the main SDHook host. Projects with selected nodes are queued for those agents. If a node has a project root directory configured, the agent runs the project at `<node_project_root>/<project_key>`.

## Webhook URLs

For project `example`:

```text
GitHub:  POST https://sdhook.example.com/hook/github/example
Gitee:   POST https://sdhook.example.com/hook/gitee/example
Gitea:   POST https://sdhook.example.com/hook/gitea/example
GitLab:  POST https://sdhook.example.com/hook/gitlab/example
Harbor:  POST https://sdhook.example.com/hook/harbor/example
Generic: POST https://sdhook.example.com/hook/generic/example?token=example-deploy-token
```

Repository hook projects support branch and tag filters. Each project stores exactly one hook config and one webhook secret.

Secret verification:

- GitHub: `X-Hub-Signature-256`
- Gitee: `X-Gitee-Token`
- Gitea: `X-Gitea-Signature` or `X-Gogs-Signature`
- GitLab: `X-Gitlab-Token`
- Harbor: `Authorization`

Harbor also supports repository and tag filtering.

## Deploy And Rollback

SDHook runs configured project commands in the selected project target directory. Git and Docker Compose project types can probe current and target versions before and after deploy.

Deploy and rollback progress is available in the Web UI through SSE. Long-running script output is written to disk and streamed to the browser.

SDHook blocks clearly dangerous deploy commands before saving project config or running deploys, including recursive deletion of system paths, `mkfs`, `dd of=/dev/...`, reboot/shutdown commands, `curl`, `wget`, and `docker system prune -af`.

If deploy needs a remote script, download and review it manually first, then execute the local script from SDHook:

```bash
install -d /etc/sdhook/projects/blog
install -m 0700 deploy.sh /etc/sdhook/projects/blog/deploy.sh
```

Configure this command in SDHook:

```bash
bash /etc/sdhook/projects/blog/deploy.sh
```

## Nginx Reverse Proxy

Use Nginx if you want to serve SDHook with a domain name and HTTPS.

An optimized example is included in:

```text
deploy/nginx/sdhook.conf
```

It keeps normal API and static requests buffered, while disabling buffering for SSE deploy logs and agent long polling.

Typical install path:

```bash
install -m 0644 deploy/nginx/sdhook.conf /etc/nginx/conf.d/sdhook.conf
nginx -t
systemctl reload nginx
```

Replace the domain, certificate paths, and backend listen address before using it.

When running behind Cloudflare or another reverse proxy, preserve `X-Forwarded-For` or `X-Real-IP` so the node source address remains useful.

## Release Assets

GitHub releases publish separate server and agent archives:

```text
sdhook-darwin-arm64.tar.gz
sdhook-agent-darwin-arm64.tar.gz
sdhook-linux-amd64.tar.gz
sdhook-agent-linux-amd64.tar.gz
```

Server and agent archives share the same release tag. During rolling upgrades, the installed server and agent versions may temporarily differ; the Web UI shows each agent version from heartbeat data.

Each archive contains only the binary and `README.md`. Deploy templates and install scripts are kept in the repository:

```text
scripts/install.sh
scripts/install-agent.sh
deploy/sdhook/config.toml
deploy/systemd/sdhook.service.tpl
deploy/systemd/sdhook-agent.service.tpl
deploy/nginx/sdhook.conf
```

Download releases from:

```text
https://github.com/huwenlong92/sdhook/releases
```
