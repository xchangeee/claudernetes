FROM python:3.11-alpine

# Install dependencies
RUN apk add --no-cache curl ca-certificates && \
    pip install --no-cache-dir requests==2.31.0

# Create non-root user matching ArgoCD requirements
RUN adduser -D -u 999 argocd

# Copy plugin configuration to expected location
COPY plugin.yaml /home/argocd/cmp-server/config/plugin.yaml

# Copy generation script
COPY generate.py /usr/local/bin/generate.py
RUN chmod +x /usr/local/bin/generate.py

# Switch to non-root user
USER 999

# CMP server entrypoint (injected via volume mount by ArgoCD)
ENTRYPOINT ["/var/run/argocd/argocd-cmp-server"]
