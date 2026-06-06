# SdHook

SdHook is a lightweight webhook deployment tool with a built-in Web UI.

It runs as a single binary and can manage deployments for multiple projects from GitHub, Gitee, Gitea, Harbor, or a generic webhook endpoint.

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

## Run

```bash
sdhook
```

Default files:

```text
~/.sdhook/
├── config.json
├── projects/
│   └── example.json
└── logs/
```

Web UI:

```text
http://127.0.0.1:9000
```

Default login:

```text
admin / admin
```

## Custom Config

```bash
sdhook --config /etc/sdhook/config.json
```

or:

```bash
SDHOOK_CONFIG=/etc/sdhook/config.json sdhook
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

## Webhook URLs

Project `example`:

```text
GitHub:  POST http://server:9000/hook/github/example
Gitee:   POST http://server:9000/hook/gitee/example
Gitea:   POST http://server:9000/hook/gitea/example
Harbor:  POST http://server:9000/hook/harbor/example
Generic: POST http://server:9000/hook/generic/example?token=example-deploy-token
```

The Web UI also provides copy buttons for webhook URLs.

## Releases

Download binaries from:

```text
https://github.com/huwenlong92/sdhook/releases
```
