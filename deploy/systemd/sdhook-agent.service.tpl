[Unit]
Description=SDHook Agent
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User={{USER}}
Group={{GROUP}}
WorkingDirectory={{WORKING_DIR}}
ExecStart={{BIN}} --config {{CONFIG}}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
