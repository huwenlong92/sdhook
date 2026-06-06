# SdHook

SdHook is a lightweight webhook deployment tool with a built-in Web UI.

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
│   └── example.json
└── logs/
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

Projects are stored as JSON files under `projects_dir`. The Web UI can create and edit project files directly.

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

Example unit:

```ini
[Unit]
Description=SdHook webhook deployment service
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

Common commands:

```bash
systemctl daemon-reload
systemctl enable --now sdhook
systemctl status sdhook
systemctl restart sdhook
systemctl stop sdhook
```

## Upgrade

Run the installer again:

```bash
curl -fsSL https://raw.githubusercontent.com/huwenlong92/sdhook/main/scripts/install.sh | sh
```

Then restart your service:

```bash
systemctl restart sdhook
```

## Releases

Download binaries from:

```text
https://github.com/huwenlong92/sdhook/releases
```
