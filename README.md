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

Default files:

```text
~/.sdhook/
├── config.json
├── projects/
│   └── example/
│       ├── example.json
│       └── logs/
│           └── deploy.log
```

## Config

Use a custom config file:

```bash
sdhook --config /etc/sdhook/config.json
```

or:

```bash
SDHOOK_CONFIG=/etc/sdhook/config.json sdhook
```

Main config:

```json
{
  "port": 9000,
  "admin": {
    "username": "admin",
    "password": "admin"
  },
  "webhook_secret": "",
  "projects_dir": "projects"
}
```

Projects are stored as directories under `projects_dir`. The Web UI can create and edit project files directly.

```text
projects/<project>/
├── <project>.json
└── logs/
    └── deploy.log
```

When a project is removed from the Web UI, SDHook renames its config to `<project>.json.disabled`. Disabled files are not loaded into the UI. To remove a project permanently, delete the whole `projects/<project>/` directory.

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

For GitHub, `webhook_secret` verifies `X-Hub-Signature-256`.

For GitLab, `webhook_secret` verifies `X-Gitlab-Token`.

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
sudo sdhook install-systemd
```

This command creates `/etc/sdhook/config.json`, `/etc/sdhook/projects/example/example.json`, `/etc/sdhook/projects/example/logs/`, the `sdhook` system user with UID/GID `9801`, and `/etc/systemd/system/sdhook.service`. It also runs `systemctl daemon-reload` and `systemctl enable --now sdhook`.

Create files and the unit without starting the service:

```bash
sudo sdhook install-systemd --no-start
```

Use a custom config or binary path:

```bash
sudo sdhook install-systemd --config /etc/sdhook/config.json --bin /usr/local/bin/sdhook
```

Run the service as root:

```bash
sudo sdhook install-systemd --user root --group root --uid 0 --gid 0
```

Root mode is useful when deployment commands need direct access to `docker compose`, project directories, or system services. Be careful: webhook-triggered commands will also run as root.

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
sudo sdhook install-systemd --uid 9801 --gid 9801
```

Or migrate to root mode:

```bash
sudo systemctl stop sdhook
sudo userdel sdhook
sudo groupdel sdhook 2>/dev/null || true
sudo sdhook install-systemd --user root --group root --uid 0 --gid 0
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
ExecStart=/usr/local/bin/sdhook --config /etc/sdhook/config.json
Restart=always
RestartSec=3
WorkingDirectory=/etc/sdhook

[Install]
WantedBy=multi-user.target
```

The source template is stored at:

```text
packaging/systemd/sdhook.service.tpl
```

`sdhook install-systemd` renders the embedded template and replaces `{{USER}}`, `{{GROUP}}`, `{{BIN}}`, `{{CONFIG}}`, and `{{WORKING_DIR}}`.

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

Deployment logs are stored under `projects/<project>/logs/deploy.log` and are also available in the Web UI project detail page.

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

Upgrade to the latest release:

```bash
sdhook upgrade
```

Upgrade to a specific version:

```bash
sdhook upgrade 0.1.1
```

Restart your service:

```bash
systemctl restart sdhook
```

If SDHook is installed under `/usr/local/bin` and your user cannot write there:

```bash
sudo sdhook upgrade
sudo systemctl restart sdhook
```

## Releases

Download binaries from:

```text
https://github.com/huwenlong92/sdhook/releases
```
