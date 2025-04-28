bash /notebooks/start.sh && \
PIP_DISABLE_PIP_VERSION_CHECK=1 jupyter lab \
  --allow-root \
  --ip=0.0.0.0 \
  --port=8888 \
  --no-browser \
  --ServerApp.trust_xheaders=True \
  --ServerApp.disable_check_xsrf=True \
  --ServerApp.allow_remote_access=True \
  --ServerApp.allow_origin='*' \
  --ServerApp.allow_credentials=True \
  --ServerApp.token='' \
  --ServerApp.password='' \
  --ServerApp.base_url=${PS_BASE_URI:-/}

--
git update-index --chmod=+x start.sh