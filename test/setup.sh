#!/bin/bash
set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    echo_info "Checking prerequisites..."

    if ! command -v kind &> /dev/null; then
        echo_error "kind not found. Install from: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
        exit 1
    fi

    if ! command -v kubectl &> /dev/null; then
        echo_error "kubectl not found. Install from: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi

    if ! command -v docker &> /dev/null; then
        echo_error "docker not found. Install from: https://docs.docker.com/get-docker/"
        exit 1
    fi

    echo_info "All prerequisites met!"
}

# Create kind cluster
create_cluster() {
    echo_info "Creating kind cluster..."

    if kind get clusters | grep -q "^claudernetes-test$"; then
        echo_warn "Cluster 'claudernetes-test' already exists. Delete it? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            kind delete cluster --name claudernetes-test
        else
            echo_info "Using existing cluster"
            return
        fi
    fi

    kind create cluster --config kind-config.yaml
    echo_info "Cluster created successfully!"
}

# Build and load CMP image
build_and_load_image() {
    echo_info "Building claudernetes CMP image..."

    cd ..
    docker build -t claudernetes-cmp:local .
    cd test

    echo_info "Loading image into kind cluster..."
    kind load docker-image claudernetes-cmp:local --name claudernetes-test

    echo_info "Image loaded successfully!"
}

# Install ArgoCD
install_argocd() {
    echo_info "Installing ArgoCD..."

    kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -

    # Install minimal ArgoCD
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

    echo_info "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-repo-server -n argocd

    echo_info "ArgoCD installed successfully!"
}

# Create API key secret
create_api_key_secret() {
    echo_info "Creating Anthropic API key secret..."

    if [ -z "$ANTHROPIC_API_KEY" ]; then
        echo_warn "ANTHROPIC_API_KEY environment variable not set"
        echo_warn "Please enter your Anthropic API key:"
        read -r api_key
    else
        api_key="$ANTHROPIC_API_KEY"
    fi

    kubectl create secret generic anthropic-api-key \
        --from-literal=api-key="$api_key" \
        -n argocd \
        --dry-run=client -o yaml | kubectl apply -f -

    echo_info "API key secret created!"
}

# Patch argocd-repo-server with CMP sidecar
patch_repo_server() {
    echo_info "Patching argocd-repo-server with CMP sidecar..."

    kubectl patch deployment argocd-repo-server -n argocd --patch-file argocd-repo-server-patch.yaml

    echo_info "Waiting for patched repo-server to be ready..."
    kubectl rollout status deployment/argocd-repo-server -n argocd --timeout=300s

    echo_info "Repo server patched successfully!"
}

# Install Gitea
install_gitea() {
    echo_info "Installing Gitea (local git server)..."

    kubectl apply -f gitea.yaml

    echo_info "Waiting for Gitea to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/gitea -n git-server

    # Wait a bit more for Gitea to fully initialize
    sleep 10

    echo_info "Gitea installed successfully!"
}

# Deploy test application
deploy_test_app() {
    echo_info "Deploying test ArgoCD Application..."

    kubectl apply -f test-app-application.yaml

    echo_info "Test application created! Check ArgoCD UI to see it sync."
}

# Get ArgoCD password
get_argocd_password() {
    echo_info "Retrieving ArgoCD admin password..."

    password=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)

    echo ""
    echo "======================================"
    echo_info "ArgoCD Setup Complete!"
    echo "======================================"
    echo ""
    echo "ArgoCD UI: http://localhost:8080"
    echo "Username: admin"
    echo "Password: $password"
    echo ""
    echo "To access ArgoCD:"
    echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo ""
    echo "To check CMP logs:"
    echo "  kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server -c claudernetes"
    echo ""
    echo "To test the plugin:"
    echo "  kubectl apply -f test-app-application.yaml"
    echo ""
    echo "======================================"
}

# Main execution
main() {
    echo_info "Starting claudernetes local test setup..."
    echo ""

    check_prerequisites
    create_cluster
    build_and_load_image
    install_gitea
    install_argocd
    create_api_key_secret
    patch_repo_server
    get_argocd_password

    echo ""
    echo_info "Setup complete! Infrastructure is ready."
    echo ""
    echo "======================================"
    echo_info "Next Steps:"
    echo "======================================"
    echo ""
    echo "1. Create the test repository:"
    echo "   ./create-test-repo.sh"
    echo ""
    echo "2. Access ArgoCD UI:"
    echo "   kubectl port-forward svc/argocd-server -n argocd 8080:443"
    echo "   Then visit: https://localhost:8080"
    echo ""
    echo "3. Access Gitea UI (optional):"
    echo "   kubectl port-forward -n git-server svc/gitea 3000:3000"
    echo "   Then visit: http://localhost:3000"
    echo "   Credentials: test / test123"
    echo ""
    echo "======================================"
}

# Run main function
main
