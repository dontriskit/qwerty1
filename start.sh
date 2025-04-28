#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Starting VLLM setup and Tailscale script..."
echo "Running as user: $(whoami)" # Should be root

# --- Prerequisite Installation ---
echo "Updating apt cache..."
apt-get update -y

echo "Installing prerequisites (gcc, curl)..."
# We still need curl to fetch the script, and gcc for vLLM compilation if needed.
apt-get install -y --no-install-recommends \
    gcc \
    curl \
    ca-certificates

echo "Cleaning up apt cache..."
apt-get clean
rm -rf /var/lib/apt/lists/*

# --- vLLM Installation ---
echo "Installing vLLM python package..."
# Use --root-user-action=ignore to suppress the pip warning
pip install --no-cache-dir vllm --root-user-action=ignore
echo ">>> Note: Ignore potential RAPIDS/cuDF/numba dependency warnings above if only using vLLM. <<<"

# --- Tailscale Installation (using universal install.sh script) ---
echo "Installing Tailscale using install.sh..."
# This script handles adding repo, keys, and installing via apt/dnf/etc.
curl -fsSL https://tailscale.com/install.sh | sh
echo "Tailscale installed via install.sh."

# --- Tailscale Setup ---
echo "Starting Tailscale daemon in background..."
# Start the daemon. Running as root, so no sudo needed.
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 --outbound-http-proxy-listen=localhost:1055 &

# Give the daemon a moment to initialize
sleep 3

# Check if the TAILSCALE_AUTH_KEY secret is provided
if [ -z "$TAILSCALE_AUTH_KEY" ]; then
  echo "ERROR: TAILSCALE_AUTH_KEY secret is not set in Gradient!"
  echo "Please add the secret to your project."
  exit 1 # Exit script with an error
fi

echo "Connecting to Tailscale network (no sudo needed as root)..."
# Connect using the auth key. Use a clear hostname.
tailscale up \
  --authkey=${TAILSCALE_AUTH_KEY} \
  --hostname=gradient-vllm-node \
  --accept-routes \
  --accept-dns=false \
  --force-reauth || { echo "Tailscale connection failed!"; exit 1; } # Exit if connection fails

echo "Tailscale connected successfully. Tailscale IP Address:"
tailscale ip -4 # Print the Tailscale IP for logs

# --- Start vLLM Server ---
MODEL_NAME="gaunernst/gemma-3-12b-it-qat-autoawq" # Or make this dynamic if needed
echo "Starting vLLM server for model: $MODEL_NAME in the background..."
echo "vLLM output will be minimal here; monitor GPU/process usage."

# Start vLLM in the background. Listens on Tailscale IP due to 0.0.0.0
vllm serve $MODEL_NAME --host 0.0.0.0 --port 8000 &

# Brief pause to let vllm start or fail quickly
sleep 5

# Optional: Check if vLLM process started (simple check)
if pgrep -f "vllm serve" > /dev/null; then
    echo "vLLM server process appears to be running."
else
    echo "WARNING: vLLM server process might not have started correctly."
fi

echo "Setup script finished. Background processes launched."
echo "Proceeding to start Jupyter Lab..."
# Script ends, Gradient command continues with Jupyter Lab