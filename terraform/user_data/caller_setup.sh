#!/bin/bash
###############################################################################
# caller_setup.sh — bootstrap script for the Caller Worker VM (API Gateway)
# Runs once on first boot via EC2 user_data (as root)
#
# Templatefile variables (injected by Terraform):
#   ${inference_private_ip} — private IP of the inference VM
#   ${iii_ws_port}          — WebSocket port for RPC (default 49134)
#   ${iii_http_port}        — HTTP port the API listens on (default 3111)
###############################################################################
set -euxo pipefail
exec > /var/log/caller_setup.log 2>&1

###############################################################################
# 1. System packages
###############################################################################
apt-get update -y
apt-get install -y \
  git \
  curl \
  wget \
  unzip \
  htop

###############################################################################
# 2. Install Node.js 20.x (LTS)
###############################################################################
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs
node --version
npm --version

###############################################################################
# 3. Install the iii CLI (RPC engine)
###############################################################################
export HOME=/root
curl -fsSL https://install.iii.dev/iii/main/install.sh | sh
mv /root/.local/bin/iii* /usr/local/bin/ || true

###############################################################################
# 4. Clone the project repo
###############################################################################
REPO_DIR="/opt/devops-iii"
REPO_URL="https://github.com/sk0990670/Alchemyst-ai-Devops-Assignment.git"

git clone "$REPO_URL" "$REPO_DIR"
chown -R ubuntu:ubuntu "$REPO_DIR"

###############################################################################
# 5. Install TypeScript worker dependencies
###############################################################################
WORKER_DIR="$REPO_DIR/quickstart/workers/caller-worker"

sudo -u ubuntu bash -c "
  cd $WORKER_DIR
  npm install
  npm install iii-sdk@latest
"

###############################################################################
# 6. Write iii engine config for this VM
#    Caller worker only — HTTP endpoint on port ${iii_http_port}
#    RPC calls go TO the inference VM's private IP:${iii_ws_port}
###############################################################################
cat > /opt/devops-iii/quickstart/config.yaml <<YAML
workers:
  - name: iii-observability
    config:
      enabled: true
      service_name: iii-caller
      exporter: memory
      memory_max_spans: 5000
      metrics_enabled: true
      metrics_exporter: memory
      logs_enabled: true
      logs_exporter: memory
      logs_console_output: true
      sampling_ratio: 1.0

  - name: iii-queue
    config:
      adapter:
        name: builtin

  - name: iii-http
    config:
      port: ${iii_http_port}
      host: 0.0.0.0
      default_timeout: 30000
      concurrency_request_limit: 1024
      cors:
        allowed_origins:
          - '*'
        allowed_methods:
          - GET
          - POST
          - PUT
          - DELETE
          - OPTIONS

YAML

###############################################################################
# 7. Systemd service for the iii engine on caller VM
###############################################################################
cat > /etc/systemd/system/iii-engine.service <<SERVICE
[Unit]
Description=iii RPC Engine (Caller / API Gateway)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/devops-iii/quickstart
ExecStart=/usr/local/bin/iii --config config.yaml
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=iii-engine

[Install]
WantedBy=multi-user.target
SERVICE

###############################################################################
# 8. Systemd service for the caller worker
#    III_URL points to the INFERENCE VM's private IP so RPC calls are routed
#    across the private subnet — never over the public internet.
###############################################################################
cat > /etc/systemd/system/caller-worker.service <<SERVICE
[Unit]
Description=iii Caller Worker (TypeScript — HTTP API)
After=iii-engine.service
Requires=iii-engine.service

[Service]
Type=simple
User=ubuntu
WorkingDirectory=$WORKER_DIR
# Caller connects to the inference VM via private IP — this is the key wiring
Environment="III_URL=ws://localhost:${iii_ws_port}"
ExecStart=/usr/bin/npm run dev
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=caller-worker

[Install]
WantedBy=multi-user.target
SERVICE

###############################################################################
# 9. Enable and start services
###############################################################################
systemctl daemon-reload
systemctl enable iii-engine
systemctl enable caller-worker
systemctl start iii-engine
sleep 5
systemctl start caller-worker

echo "=== caller-worker bootstrap complete ==="
echo "API available at: http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):${iii_http_port}/v1/chat/completions"
