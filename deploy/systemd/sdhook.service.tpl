[Unit]
Description=SDHook webhook deployment service
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User={{USER}}
Group={{GROUP}}
ExecStart={{BIN}} --config {{CONFIG}}
Restart=always
RestartSec=3
WorkingDirectory={{WORKING_DIR}}

[Install]
WantedBy=multi-user.target
