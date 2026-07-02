[Unit]
Description=SDHook Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User={{USER}}
Group={{GROUP}}
WorkingDirectory={{WORKING_DIR}}
EnvironmentFile={{ENV_FILE}}
ExecStart={{BIN}}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
