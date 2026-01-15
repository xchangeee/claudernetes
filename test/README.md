# Local Testing Setup for Claudernetes

This directory contains everything needed to test claudernetes locally using kind (Kubernetes in Docker).

## Quick Start

Run the setup script from this directory:

```bash
cd test
export ANTHROPIC_API_KEY=your-api-key-here
./setup.sh
```

The script will:

1. Create a kind cluster named `claudernetes-test`
2. Build the claudernetes CMP Docker image
3. Load the image into the kind cluster
4. Install Gitea (local git server)
5. Install ArgoCD
6. Configure the API key secret
7. Patch argocd-repo-server with the CMP sidecar
8. Create test repository in Gitea
9. Display connection info

## Access Services

### ArgoCD UI

```bash
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

Then open [http://localhost:8080](http://localhost:8080)

Login credentials will be displayed by the setup script.

### Gitea (Local Git Server)

```bash
kubectl port-forward -n git-server svc/gitea 3000:3000
```

Then open [http://localhost:3000](http://localhost:3000)

- Username: `test`
- Password: `test123`

The test repository is at: [http://localhost:3000/test/test-app](http://localhost:3000/test/test-app)

## Test the Plugin

The setup includes a test application in [test-app/](test-app/) with a simple nginx deployment.

To deploy it:

```bash
kubectl apply -f test-app-application.yaml
```

Watch it sync in the ArgoCD UI or via CLI:

```bash
kubectl get application -n argocd claudernetes-test-app
```

## Check Plugin Logs

View the CMP sidecar logs:

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -c claudernetes -f
```

View ArgoCD repo-server logs:

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -c argocd-repo-server -f
```

## Modify Test Instructions

You can modify the test application in two ways:

### Option 1: Via Gitea UI

1. Access Gitea at [http://localhost:3000](http://localhost:3000)
2. Navigate to the test/test-app repository
3. Edit `claudernetes.yaml`
4. Commit the changes
5. ArgoCD will automatically detect and sync

### Option 2: Via Git CLI

```bash
# Clone the repo from Gitea
git clone http://localhost:3000/test/test-app.git
cd test-app

# Make changes
vim claudernetes.yaml

# Commit and push
git add .
git commit -m "Update instructions"
git push

# ArgoCD will automatically sync
```

After pushing changes, ArgoCD will:

1. Detect the change
2. Call the claudernetes CMP
3. Generate new manifests
4. Sync to the cluster

## Iterate on the Plugin

To test changes to the plugin code:

```bash
# Make changes to generate.py, plugin.yaml, or Dockerfile
cd ..
docker build -t claudernetes-cmp:local .
kind load docker-image claudernetes-cmp:local --name claudernetes-test

# Restart the repo-server to pick up new image
kubectl rollout restart deployment/argocd-repo-server -n argocd
kubectl rollout status deployment/argocd-repo-server -n argocd
```

## Files

- [kind-config.yaml](kind-config.yaml) - kind cluster configuration with port mappings
- [setup.sh](setup.sh) - Automated setup script
- [gitea.yaml](gitea.yaml) - Gitea local git server deployment
- [argocd-repo-server-patch.yaml](argocd-repo-server-patch.yaml) - Patch to add CMP sidecar
- [test-app/claudernetes.yaml](test-app/claudernetes.yaml) - Example instructions for Claude
- [test-app-application.yaml](test-app-application.yaml) - ArgoCD Application manifest
- [teardown.sh](teardown.sh) - Cleanup script to delete the cluster

## Cleanup

Delete the test cluster:

```bash
kind delete cluster --name claudernetes-test
```

## Troubleshooting

### Plugin Not Detected

Check that the plugin is registered:

```bash
kubectl exec -n argocd deployment/argocd-repo-server -c argocd-repo-server -- argocd-cmp-server --list
```

### API Key Issues

Verify the secret is mounted:

```bash
kubectl exec -n argocd deployment/argocd-repo-server -c claudernetes -- ls -la /var/run/secrets/anthropic-api-key/
```

### Image Not Found

Verify the image is loaded in kind:

```bash
docker exec -it claudernetes-test-control-plane crictl images | grep claudernetes
```

### Generation Failures

Check the CMP logs for errors:

```bash
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -c claudernetes --tail=50
```

## Testing Different Scenarios

Create additional test apps in Gitea:

```bash
# Port-forward to Gitea
kubectl port-forward -n git-server svc/gitea 3000:3000 &

# Clone and create a new test app
git clone http://test:test123@localhost:3000/test/test-app.git redis-test
cd redis-test

# Modify the instructions
cat > claudernetes.yaml <<EOF
instructions: |
  Create a Redis deployment with:
  - StatefulSet with 1 replica
  - PersistentVolumeClaim for 1Gi storage
  - Headless service
  - ConfigMap with redis.conf
EOF

# Push as a new repo
git add .
git commit -m "Redis test app"

# Create new repo in Gitea via API
curl -X POST "http://localhost:3000/api/v1/user/repos" \
    -H "Content-Type: application/json" \
    -u test:test123 \
    -d '{"name": "redis-test", "private": false}'

git remote set-url origin http://test:test123@localhost:3000/test/redis-test.git
git push -u origin master

# Create ArgoCD Application
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: redis-test
  namespace: argocd
spec:
  project: default
  source:
    repoURL: http://gitea.git-server.svc.cluster.local:3000/test/redis-test.git
    targetRevision: HEAD
    plugin:
      name: claudernetes
  destination:
    server: https://kubernetes.default.svc
    namespace: default
EOF
```

## Development Workflow

1. Make changes to [generate.py](../generate.py)
2. Rebuild: `docker build -t claudernetes-cmp:local ..`
3. Reload: `kind load docker-image claudernetes-cmp:local --name claudernetes-test`
4. Restart: `kubectl rollout restart deployment/argocd-repo-server -n argocd`
5. Test: Trigger a sync in ArgoCD or modify test-app instructions

## Manual Testing

Test the generate script locally:

```bash
cd test/test-app
export ANTHROPIC_API_KEY=your-key
python3 ../../generate.py
```

Note: This requires the API key to be at the hardcoded path. For local testing, you can temporarily modify [generate.py](../generate.py) to read from environment variable.
