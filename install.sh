#!/bin/bash

# --- 1. SETUP ---
if [ -z "$SUDO_USER" ]; then
    echo "Error: This script must be run using sudo."
    exit 1
fi
KLIPPER_USER="$SUDO_USER"
PLUGIN_DIR=$(pwd)
SERVICE_NAME="klipper-print-failure-detection"

echo "Detected User: $KLIPPER_USER"
echo "Installation Directory: $PLUGIN_DIR"

# --- 2. Detect Python 3.11 for tflite-runtime compatibility ---
PYTHON_BIN="python3"
PYTHON_VERSION=$("$PYTHON_BIN" -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null)

if [ "$PYTHON_VERSION" != "3.11" ]; then
    echo "System Python is $PYTHON_VERSION — looking for Python 3.11 via pyenv..."
    if command -v pyenv &>/dev/null; then
        PYENV_ROOT=$(pyenv root 2>/dev/null || echo "$HOME/.pyenv")
        PYTHON_311=$(ls "$PYENV_ROOT/versions/" 2>/dev/null | grep "^3\.11" | head -1)
        if [ -n "$PYTHON_311" ]; then
            PYTHON_BIN="$PYENV_ROOT/versions/$PYTHON_311/bin/python"
            echo "Using Python $PYTHON_311 from pyenv"
        else
            echo "ERROR: Python 3.11 not found in pyenv versions."
            echo "Install it first: pyenv install 3.11.9"
            exit 1
        fi
    else
        echo "ERROR: pyenv not found and system Python is not 3.11."
        echo "Install Python 3.11 first: pyenv install 3.11.9"
        exit 1
    fi
fi

# --- 3. Install System Dependencies ---
echo "Installing system libraries..."
sudo apt-get update && sudo apt-get install -y python3-opencv libopenjp2-7 libopenblas-dev

# --- 4. Create Virtual Environment ---
if [ ! -d "$PLUGIN_DIR/venv" ]; then
    echo "Creating Python virtual environment with $PYTHON_BIN..."
    sudo -u "$KLIPPER_USER" $PYTHON_BIN -m venv "$PLUGIN_DIR/venv"
fi

# --- 5. Install Python Requirements ---
echo "------------------------------------------------"
echo "INSTALLING TFLITE RUNTIME"
echo "------------------------------------------------"
sudo -u "$KLIPPER_USER" "$PLUGIN_DIR/venv/bin/pip" install --no-cache-dir -r "$PLUGIN_DIR/requirements.txt"

# --- 6. Permissions Fix ---
echo "Fixing permissions..."
chown -R "$KLIPPER_USER":"$KLIPPER_USER" "$PLUGIN_DIR"

# --- 7. Service Creation ---
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
echo "Creating Systemd service..."

cat > $SERVICE_FILE <<EOF
[Unit]
Description=Klipper Print Failure Detection (Custom TFLite)
After=network.target

[Service]
Type=simple
User=$KLIPPER_USER
ExecStart=$PLUGIN_DIR/venv/bin/python $PLUGIN_DIR/plugin.py
WorkingDirectory=$PLUGIN_DIR
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# --- 8. Enable Service ---
echo "Enabling service..."
systemctl daemon-reload
systemctl enable "$SERVICE_NAME".service
systemctl restart "$SERVICE_NAME".service

echo "------------------------------------------------"
echo "Installation Complete!"
echo "Access the failure detection dashboard at"
echo "http://<YOUR-PRINTER-IP>:7126"
echo "------------------------------------------------"
