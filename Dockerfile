FROM docker.io/library/python:3.14-slim-bookworm
RUN useradd -m -u 999 argocd
RUN <<EOF
apt-get update
apt-get install -y --no-install-recommends curl ca-certificates
apt-get clean
rm -rf /var/lib/apt/lists/*
pip install --no-cache-dir requests==2.31.0
EOF

COPY plugin.yaml /home/argocd/cmp-server/config/plugin.yaml
COPY --chmod=755 generate.py /usr/local/bin/generate.py

USER 999
ENTRYPOINT ["/var/run/argocd/argocd-cmp-server"]
