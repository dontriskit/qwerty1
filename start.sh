#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Starting VLLM setup and Tailscale script..."
echo "Running as user: $(whoami)" # Good to check if running as root

# --- Dependency Installation ---
echo "Updating apt cache..."
apt-get update -y

echo "Installing prerequisites (gcc, curl, tailscale dependencies)..."
# --no-install-recommends helps keep the install size smaller
apt-get install -y --no-install-recommends \
    gcc \
    curl \
    ca-certificates \
    gnupg \
    lsb-release

echo "Cleaning up apt cache..."
apt-get clean
rm -rf /var/lib/apt/lists/*

echo "Installing vLLM python package..."
# Use --no-cache-dir to avoid filling up space with pip cache
pip install --no-cache-dir vllm

echo "Installing Tailscale..."
# Download and execute the official Tailscale installation script
curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs)/installer.sh | bash
echo "Tailscale installed."

# --- Tailscale Setup ---
echo "Starting Tailscale daemon in background..."
# Start the daemon. Using userspace-networking often avoids permissions issues in containers.
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 --outbound-http-proxy-listen=localhost:1055 &

# Give the daemon a moment to initialize
sleep 3

# Check if the TAILSCALE_AUTH_KEY secret is provided
if [ -z "$TAILSCALE_AUTH_KEY" ]; then
  echo "ERROR: TAILSCALE_AUTH_KEY secret is not set in Gradient!"
  echo "Please add the secret to your project."
  exit 1 # Exit script with an error
fi

echo "Connecting to Tailscale network..."
# Connect using the auth key. Use a clear hostname.
# --accept-dns=false is often safer in managed environments unless you specifically need Tailscale DNS.
# --force-reauth helps if restarting the container with the same hostname
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

# Start vLLM in the background. Using 0.0.0.0 makes it listen on all interfaces, including Tailscale's.
# Redirecting output might be useful for debugging, but for now, let it go to container logs.
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
# The script ends here. The '&&' in the Gradient command will now execute Jupyter.