#!/bin/bash
###############################################################################
# inference_setup.sh — bootstrap script for the Inference Worker VM
# Runs once on first boot via EC2 user_data (as root)
#
# Templatefile variables (injected by Terraform):
#   ${iii_ws_port}  — WebSocket port the iii engine listens on (default 49134)
###############################################################################
set -euxo pipefail
exec > /var/log/inference_setup.log 2>&1

###############################################################################
# 1. System packages
###############################################################################
apt-get update -y
apt-get install -y \
  python3 \
  python3-pip \
  python3-venv \
  git \
  curl \
  wget \
  unzip \
  htop

###############################################################################
# 2. Install the iii CLI (RPC engine)
###############################################################################
curl -fsSL https://iii.dev/install.sh | sh
# Make iii available system-wide
ln -sf /root/.iii/bin/iii /usr/local/bin/iii || true

###############################################################################
# 3. Clone the project repo
###############################################################################
REPO_DIR="/opt/devops-iii"
REPO_URL="https://github.com/sk0990670/Alchemyst-ai-Devops-Assignment.git"

git clone "$REPO_URL" "$REPO_DIR"
chown -R ubuntu:ubuntu "$REPO_DIR"

###############################################################################
# 4. Set up Python virtualenv & install worker dependencies
###############################################################################
WORKER_DIR="$REPO_DIR/quickstart/workers/inference-worker"

sudo -u ubuntu bash -c "
  python3 -m venv $WORKER_DIR/venv
  source $WORKER_DIR/venv/bin/activate
  pip install --upgrade pip
  pip install -r $WORKER_DIR/requirements.txt
"

###############################################################################
# 5. Write the iii engine config for this VM
#    (only runs inference-worker here; caller-worker is on a separate VM)
###############################################################################
cat > /opt/devops-iii/quickstart/config-inference.yaml <<YAML
workers:
  - name: iii-observability
    config:
      enabled: true
      service_name: iii-inference
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

  - name: iii-state
    config:
      adapter:
        name: kv
        config:
          store_method: file_based
          file_path: /opt/devops-iii/data/state_store.db

  - name: inference-worker
    worker_path: $WORKER_DIR
YAML

mkdir -p /opt/devops-iii/data
chown -R ubuntu:ubuntu /opt/devops-iii/data

###############################################################################
# 6. Create systemd service — inference-worker starts on boot
###############################################################################
cat > /etc/systemd/system/inference-worker.service <<SERVICE
[Unit]
Description=iii Inference Worker (Python + Gemma)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=$WORKER_DIR
Environment="III_URL=ws://localhost:${iii_ws_port}"
ExecStart=$WORKER_DIR/venv/bin/python inference_worker.py
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=inference-worker

[Install]
WantedBy=multi-user.target
SERVICE

###############################################################################
# 7. Create systemd service — iii engine starts on boot (manages the workers)
###############################################################################
cat > /etc/systemd/system/iii-engine.service <<SERVICE
[Unit]
Description=iii RPC Engine
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=ubuntu
WorkingDirectory=/opt/devops-iii/quickstart
ExecStart=/usr/local/bin/iii start --config config-inference.yaml
Restart=on-failure
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=iii-engine

[Install]
WantedBy=multi-user.target
SERVICE

###############################################################################
# 8. Enable and start services
###############################################################################
systemctl daemon-reload
systemctl enable iii-engine
systemctl enable inference-worker
systemctl start iii-engine
# Give engine a moment to initialise before starting the worker
sleep 5
systemctl start inference-worker

echo "=== inference-worker bootstrap complete ==="
