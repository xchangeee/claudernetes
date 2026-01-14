# claudernetes

ArgoCD Config Management Plugin (CMP) that uses Claude API to dynamically generate Kubernetes manifests from natural language instructions.

## What is claudernetes?

claudernetes lets you describe your Kubernetes infrastructure in plain English instead of writing YAML. Put a `claudernetes.yaml` file in your Git repo with instructions, and ArgoCD + Claude will generate production-ready manifests automatically.

## Features

- **Natural Language to K8s**: Describe what you want, Claude generates the YAML
- **ArgoCD Native**: Standard CMP sidecar pattern
- **Production Ready**: Best practices built into Claude's system prompt
- **Simple Setup**: Minimal dependencies (Python + requests)
- **Secure**: API key from Kubernetes Secret, runs as non-root

## Prerequisites

- ArgoCD installed in your cluster
- Anthropic API key ([get one here](https://console.anthropic.com/))
- kubectl access to ArgoCD namespace

## Installation

### 1. Create API Key Secret

```bash
kubectl create secret generic anthropic-api-key \
  --from-literal=api-key=your-anthropic-api-key-here \
  -n argocd
```

### 2. Build and Push Docker Image

```bash
docker build -t ghcr.io/yourorg/claudernetes:latest .
docker push ghcr.io/yourorg/claudernetes:latest
```

### 3. Patch argocd-repo-server

```bash
kubectl patch deployment argocd-repo-server \
  -n argocd \
  --patch-file examples/argocd-repo-server-patch.yaml
```

Alternatively, use Kustomize or Helm to add the sidecar.

### 4. Verify Installation

```bash
# Check sidecar is running
kubectl get pods -n argocd -l app.kubernetes.io/name=argocd-repo-server

# Check logs
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -c claudernetes
```

## Usage

### 1. Create claudernetes.yaml in Your Repo

```yaml
# claudernetes.yaml
instructions: |
  Create a production deployment for my FastAPI application:

  - Image: myregistry/fastapi-app:v1.0.0
  - 3 replicas
  - Expose on port 8000
  - Add health checks on /health endpoint
  - Set resource limits appropriately
  - Include a Service and Ingress with TLS
```

### 2. Create ArgoCD Application

```bash
kubectl apply -f examples/application.yaml
```

Or via ArgoCD UI:

1. Click "New App"
2. Set repo URL and path
3. Under "Plugin", select "claudernetes"
4. Deploy

### 3. ArgoCD Generates Manifests

ArgoCD will:

1. Detect `claudernetes.yaml` in your repo
2. Call claudernetes CMP sidecar
3. Claude API generates K8s manifests
4. ArgoCD syncs them to your cluster

## How It Works

```text
┌─────────────────┐
│   Git Repo      │
│                 │
│ claudernetes.yaml│
│ (instructions)  │
└────────┬────────┘
         │
         │ ArgoCD sync
         ↓
┌─────────────────────────────────────┐
│   argocd-repo-server                │
│                                     │
│  ┌──────────────────────────────┐  │
│  │ claudernetes CMP sidecar     │  │
│  │                              │  │
│  │ 1. Read claudernetes.yaml    │  │
│  │ 2. Read API key from secret  │  │
│  │ 3. Call Claude API           │  │
│  │ 4. Return K8s YAML           │  │
│  └──────────────────────────────┘  │
└─────────────────────────────────────┘
         │
         │ Generated manifests
         ↓
┌─────────────────┐
│   Kubernetes    │
│   Cluster       │
└─────────────────┘
```

## Examples

### Simple Deployment

```yaml
instructions: |
  Deploy nginx with 2 replicas and a LoadBalancer service
```

### Complex Multi-Resource

```yaml
instructions: |
  Create a complete setup for Redis:
  - StatefulSet with 3 replicas
  - Persistent storage (1Gi per pod)
  - ConfigMap for redis.conf
  - Headless service for cluster
  - Regular service for clients
  - PodDisruptionBudget
  - NetworkPolicy to allow only app pods
```

### With Specific Requirements

```yaml
instructions: |
  Deploy my microservice with these exact specs:

  Deployment:
  - Name: user-service
  - Image: myregistry/user-service:sha-abc123
  - Replicas: 5
  - Strategy: RollingUpdate (maxSurge: 1, maxUnavailable: 0)
  - Container port: 3000
  - Environment variables from ConfigMap "user-service-config"
  - Secret "user-service-secrets" for DB credentials
  - Resources: requests 100m/128Mi, limits 500m/512Mi
  - Liveness probe: HTTP GET /health every 10s
  - Readiness probe: HTTP GET /ready every 5s

  Service:
  - Type: ClusterIP
  - Port 80 -> 3000

  Also include appropriate labels and annotations for monitoring.
```

## Configuration

### System Prompt

The CMP uses this system prompt for Claude:

```text
You are an expert Site Reliability Engineer and Kubernetes architect.

Your task is to generate production-ready Kubernetes manifests based on user instructions.

Requirements:
- Generate valid, idiomatic Kubernetes YAML
- Follow best practices (resource limits, security contexts, labels, etc.)
- Use appropriate API versions
- Include helpful comments
- Ensure manifests are deployable to a standard Kubernetes cluster
- Output ONLY valid YAML - no markdown code blocks
- Multiple resources should be separated by '---'

Be concise but complete. Prioritize correctness and production-readiness.
```

You can modify this in [generate.py](generate.py) if needed.

### Model Configuration

Current settings in [generate.py](generate.py):

- Model: `claude-sonnet-4-5-20250929`
- Max tokens: 4096
- Timeout: 30s

## Troubleshooting

### Plugin Not Detected

Check ArgoCD logs:

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -c argocd-repo-server
```

Ensure `claudernetes.yaml` exists in repo root.

### API Key Issues

```bash
# Verify secret exists
kubectl get secret anthropic-api-key -n argocd

# Check sidecar can read it
kubectl exec -n argocd deployment/argocd-repo-server -c claudernetes -- ls -la /var/run/secrets/anthropic-api-key
```

### Generation Errors

View sidecar logs:

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -c claudernetes
```

Common issues:

- Invalid API key
- Network connectivity to api.anthropic.com
- Malformed instructions in claudernetes.yaml

### Invalid YAML Output

If Claude generates markdown code blocks:

1. Check system prompt is correctly set
2. Verify using latest Claude model
3. Make instructions more explicit about YAML-only output

## Security Considerations

1. **API Key Management**: Use external secret managers (e.g., External Secrets Operator, Vault) instead of plain Kubernetes Secrets in production

2. **Network Policies**: Restrict claudernetes sidecar to only api.anthropic.com

3. **RBAC**: ArgoCD's service account should have minimal permissions

4. **Image Scanning**: Scan claudernetes image for vulnerabilities

5. **Audit**: Log all Claude API calls for compliance

## Cost Management

Claude API charges per token:

- Input: Instructions from claudernetes.yaml
- Output: Generated manifests

Tips:

- Be concise in instructions
- Cache generated manifests in Git (commit Claude's output)
- Monitor API usage in Anthropic console

## Limitations

1. **Stateless**: Each generation is independent (no conversation history)
2. **Determinism**: Claude may generate slightly different manifests each time
3. **Validation**: No automatic validation of generated YAML (ArgoCD will fail on invalid resources)
4. **Secrets**: Don't put sensitive data in instructions (they're sent to Claude API)

## Roadmap

- [ ] Multi-file support (generate multiple resources in separate files)
- [ ] Template caching to reduce API calls
- [ ] Validation layer before returning manifests
- [ ] Support for parameters/values override
- [ ] Integration with policy engines (OPA, Kyverno)

## Contributing

Contributions welcome! Please:

1. Fork the repo
2. Create a feature branch
3. Submit a PR with tests

## License

MIT

## Acknowledgments

- Built on [ArgoCD CMP v2](https://argo-cd.readthedocs.io/en/stable/operator-manual/config-management-plugins/)
- Powered by [Anthropic Claude API](https://docs.anthropic.com/)
