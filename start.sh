#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
set -e

echo "--- Starting VLLM & Tailscale Initialization Script ---"
echo "Timestamp: $(date)"
echo "Running as user: $(whoami)" # Should be root if USER root is last in Dockerfile

# --- Environment Variable Checks ---
if [ -z "$TAILSCALE_AUTH_KEY" ]; then
  echo "[ERROR] TAILSCALE_AUTH_KEY secret is not set in the Gradient environment!"
  echo "        Please add the TAILSCALE_AUTH_KEY secret to your Notebook/Deployment."
  exit 1
fi

# Check for VLLM_MODEL, provide a default, or make it mandatory
if [ -z "$VLLM_MODEL" ]; then
  # Option 1: Use a default model
  echo "[WARN] VLLM_MODEL environment variable not set. Using default: mistralai/Mistral-7B-Instruct-v0.1"
  export VLLM_MODEL="mistralai/Mistral-7B-Instruct-v0.1"

  # Option 2: Make it mandatory (uncomment below to enable)
  # echo "[ERROR] VLLM_MODEL environment variable is not set."
  # echo "        Please set the VLLM_MODEL environment variable in Gradient."
  # exit 1
fi
echo "Using vLLM Model: ${VLLM_MODEL}"

# --- Tailscale Setup ---
echo "Starting Tailscale daemon (tailscaled) in background..."
# --tun=userspace-networking is often required in container environments like Gradient
# --socks5-server/--outbound-http-proxy-listen expose Tailscale proxy on localhost if needed
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 --outbound-http-proxy-listen=localhost:1055 &

# Allow tailscaled a moment to initialize before attempting to connect
sleep 5

echo "Connecting to Tailscale network..."
# Construct a unique hostname for Gradient nodes
GRADIENT_HOSTNAME="gradient-vllm-${PAPERSPACE_METRIC_WORKLOAD_ID:-$(hostname)}"
echo "Using Tailscale hostname: ${GRADIENT_HOSTNAME}"

# Connect using the auth key.
# --accept-dns=false prevents container from using Tailscale DNS servers directly, often safer.
# --force-reauth ensures the key is used even if state exists from a previous run.
tailscale up \
  --authkey="${TAILSCALE_AUTH_KEY}" \
  --hostname="${GRADIENT_HOSTNAME}" \
  --accept-routes \
  --accept-dns=false \
  --force-reauth || {
    echo "[ERROR] Tailscale 'up' command failed! Check network, auth key, or daemon status."
    # Optional: Try to kill the daemon on failure?
    # pkill tailscaled || true
    exit 1
  }

echo "Tailscale connected successfully."
# Log the assigned Tailscale IP address for easy access
TS_IP=$(tailscale ip -4) || { echo "[WARN] Failed to get Tailscale IP address."; TS_IP="<unknown>"; }
echo "Tailscale IPv4 Address: ${TS_IP}"

# --- vLLM Server Setup ---
echo "Starting vLLM OpenAI-compatible API server in background..."
echo "Model: ${VLLM_MODEL}"
echo "API will listen on 0.0.0.0:8000 inside the container."
if [ "$TS_IP" != "<unknown>" ]; then
    echo "Accessible via Tailscale at: http://${TS_IP}:8000"
fi

# Start vLLM server. Adjust flags as needed (e.g., --tensor-parallel-size, --gpu-memory-utilization).
# Run in the background (&) so the script can continue to Jupyter.
# Consider redirecting vLLM output to a file if it's too noisy in main logs:
# vllm serve ... > /var/log/vllm.log 2>&1 &
vllm serve \
    "${VLLM_MODEL}" \
    --host 0.0.0.0 \
    --port 8000 \
    &

# Allow vLLM some time to start initializing (it can take a while depending on model size)
echo "Pausing for 15 seconds to allow vLLM server to initialize..."
sleep 15

# Optional: Basic check to see if the vLLM process is running
if pgrep -f "vllm serve" > /dev/null; then
    echo "vLLM server process has been launched."
else
    echo "[WARN] vLLM server process may not have started correctly. Check container logs for errors."
fi

echo "--- Initialization Script Finished ---"
echo "Proceeding to start Jupyter Lab..."

# Exit successfully (code 0) to allow the Gradient command chain to continue
exit 0