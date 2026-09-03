#!/usr/bin/env sh
set -e

# Automated Paperclip onboarding script
# Runs as an initContainer before the main Paperclip container.
# Only executes on first start (when config.json is missing).

DATA_DIR="${DATA_DIR:-/paperclip}"
INSTANCE_DIR="${DATA_DIR}/instances/default"
CONFIG_PATH="${INSTANCE_DIR}/config.json"
MARKER_PATH="${DATA_DIR}/.onboarding-complete"

# Skip if already onboarded
if [ -f "$MARKER_PATH" ] || [ -f "$CONFIG_PATH" ]; then
    echo "[init] Paperclip config already exists, skipping onboarding"
    exit 0
fi

echo "[init] Running Paperclip onboarding..."
cd /app
pnpm paperclipai onboard --data-dir "$DATA_DIR" --yes --no-install-service || true

if [ ! -f "$CONFIG_PATH" ]; then
    echo "[init] ERROR: config.json was not created by onboard"
    exit 1
fi

echo "[init] Patching config.json for public internet access..."

# Create a Python patch script (more reliable than sed for JSON)
cat > /tmp/patch_config.py <<'PYEOF'
import json, sys, os

config_path = sys.argv[1]
public_url = sys.argv[2]
hostname = sys.argv[3]

with open(config_path, "r") as f:
    config = json.load(f)

# Override server settings for public access
config["server"] = {
    "deploymentMode": "authenticated",
    "exposure": "public",
    "bind": "lan",
    "host": "0.0.0.0",
    "port": 3100,
    "allowedHostnames": [hostname],
    "serveUi": True
}

# Ensure auth has publicBaseUrl
config["auth"] = config.get("auth", {})
config["auth"]["baseUrlMode"] = "explicit"
config["auth"]["publicBaseUrl"] = public_url
config["auth"]["disableSignUp"] = False

with open(config_path, "w") as f:
    json.dump(config, f, indent=2)

print("[patch] config.json updated for public URL:", public_url)
PYEOF

PUBLIC_URL="$PAPERCLIP_PUBLIC_URL"
HOSTNAME="$(echo "$PUBLIC_URL" | sed -e 's|https://||' -e 's|http://||' -e 's|:.*||')"

python3 /tmp/patch_config.py "$CONFIG_PATH" "$PUBLIC_URL" "$HOSTNAME"

# Create marker so next restart skips onboarding
date > "$MARKER_PATH"
echo "[init] Onboarding complete! Marker written."
