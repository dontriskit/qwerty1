#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "Starting VLLM setup script..."

# --- Dependency Installation (Only needed if you chose Path B in Step 1) ---
# echo "Updating apt and installing dependencies..."
# apt-get update -y
# apt-get install -y --no-install-recommends gcc curl ca-certificates gnupg lsb-release
# echo "Installing vLLM..."
# pip install vllm
# echo "Installing Tailscale..."
# curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/$(lsb_release -cs)/installer.sh | bash
# --- End of Dependency Installation ---

# --- Tailscale Setup ---
echo "Starting Tailscale daemon..."
# Start the Tailscale daemon in the background
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 --outbound-http-proxy-listen=localhost:1055 &

# Check if TAILSCALE_AUTH_KEY is set
if [ -z "$TAILSCALE_AUTH_KEY" ]; then
  echo "ERROR: TAILSCALE_AUTH_KEY secret is not set!"
  exit 1
fi

echo "Bringing Tailscale up..."
# Connect to Tailscale using the auth key stored as a Gradient Secret
# Using a specific hostname makes it easy to find in the Tailscale console
tailscale up --authkey=${TAILSCALE_AUTH_KEY} --hostname=gradient-vllm-node --accept-routes --accept-dns=false

echo "Tailscale connected. IP addresses:"
tailscale ip -4 # Print the Tailscale IPv4 address

# --- Start vLLM Server ---
MODEL_NAME="gaunernst/gemma-3-12b-it-qat-autoawq" # Or make this configurable via secrets/env vars
echo "Starting vLLM server for model: $MODEL_NAME in the background..."
# Start vLLM in the background. Output will go to container logs.
# Using --host 0.0.0.0 ensures it listens on all interfaces within the container (incl. the Tailscale one)
vllm serve $MODEL_NAME --host 0.0.0.0 --port 8000 &

# --- Start Jupyter Lab (as the final foreground process) ---
echo "Starting Jupyter Lab..."
# This command assumes the base image doesn't automatically start Jupyter via its CMD/ENTRYPOINT.
# If the base image *does* start Jupyter, you might only need the Tailscale and vLLM commands above,
# and then use the *default* Gradient "Command" field which handles Jupyter.
# Check your base image behavior. If using the default Gradient command, just remove this part.
# If overriding, use something like this:
# exec jupyter lab --allow-root --ip=0.0.0.0 --port=8888 --no-browser --ServerApp.token='' --ServerApp.password='' --ServerApp.base_url=${PS_BASE_URI:-/} --ServerApp.trust_xheaders=True --ServerApp.disable_check_xsrf=True
# The default Gradient command is usually more complex to handle their proxying, so it's often better
# to let the default command run *after* your background tasks are launched. See Step 4 Option 2.

echo "Startup script finished. Jupyter should be running."
# Keep the script running if Jupyter isn't the final exec, otherwise background tasks might die.
# If Jupyter is exec'd above, this isn't needed. If not, uncomment the next line:
# wait