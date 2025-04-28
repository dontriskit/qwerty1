# Start from the RAPIDS base image
FROM rapidsai/notebooks:25.04-cuda12.8-py3.12

# Metadata
LABEL maintainer="dontriskit <your-email@example.com>" # Optional: Update email
LABEL description="RAPIDS base with vLLM and Tailscale for Gradient, built via GitHub Actions"

# Switch to root user for installations
USER root

# Set DEBIAN_FRONTEND to noninteractive to avoid prompts during build
ARG DEBIAN_FRONTEND=noninteractive

# Install prerequisites
# gcc: Sometimes needed for Python package native extensions (like vLLM might use)
# curl, ca-certificates: Needed for downloading the Tailscale installer script
RUN apt-get update -y && \
    apt-get install -y --no-install-recommends \
        gcc \
        curl \
        ca-certificates \
    && \
    # Clean up apt cache to reduce image size
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# Install vLLM Python package
# Use --no-cache-dir to reduce layer size
# Use --root-user-action=ignore to suppress pip warning when running as root
# Consider pinning the vLLM version for reproducibility, e.g., vllm==0.4.0
RUN pip install --no-cache-dir vllm --root-user-action=ignore

# Install Tailscale using the official install script
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Copy the startup script into a standard location in the image
COPY start.sh /usr/local/bin/start-vllm-tailscale.sh

# Make the startup script executable
RUN chmod +x /usr/local/bin/start-vllm-tailscale.sh

# Switch back to the default jovyan user if preferred for Jupyter runtime.
# Note: start-vllm-tailscale.sh currently assumes it runs as root to manage tailscaled.
# If you switch user here, you might need to adjust start.sh or run Gradient's
# command differently (e.g., using sudo within the script, which requires passwordless sudo setup).
# Staying as root might be simpler given the --allow-root Jupyter flag.
# USER jovyan
# WORKDIR /home/jovyan/ # Or /notebooks depending on base image standard

# Define expected ports (informational only for Docker)
# 8888: Jupyter Lab (Exposed by Gradient)
# 8000: vLLM API Server (Exposed via Tailscale)
# 1055: Tailscale SOCKS5/HTTP proxy (Internal to container)
EXPOSE 8888 8000 1055

# No ENTRYPOINT or CMD needed here.
# The base image provides the default Jupyter entrypoint/command.
# The Gradient "Command" field will override the CMD to run our script first.