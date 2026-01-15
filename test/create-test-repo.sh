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

# Get the directory where this script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo_info "Setting up test application repository in Gitea..."

# Port-forward to Gitea to interact with it
echo_info "Starting port-forward to Gitea..."
kubectl port-forward -n git-server svc/gitea 3001:3000 > /dev/null 2>&1 &
PF_PID=$!
sleep 5

# Ensure port-forward is killed on script exit
trap "kill $PF_PID 2>/dev/null || true" EXIT

# Create test user
echo_info "Creating test user in Gitea..."
kubectl exec -n git-server deployment/gitea -- \
    su -s /bin/sh git -c "gitea admin user create \
    --username test \
    --password test123 \
    --email test@example.com \
    --admin \
    --must-change-password=false" 2>&1 || echo_warn "User might already exist"

sleep 1

# Create repo in Gitea via API
echo_info "Creating repository in Gitea..."
REPO_RESPONSE=$(curl -s -X POST "http://localhost:3001/api/v1/user/repos" \
    -H "Content-Type: application/json" \
    -u test:test123 \
    -d '{
        "name": "test-app",
        "description": "Claudernetes test application",
        "private": false,
        "auto_init": false
    }' 2>&1)

if echo "$REPO_RESPONSE" | grep -q "already exists"; then
    echo_warn "Repository already exists. Deleting and recreating..."
    curl -s -X DELETE "http://localhost:3001/api/v1/repos/test/test-app" \
        -u test:test123 2>&1 > /dev/null
    sleep 2
    curl -s -X POST "http://localhost:3001/api/v1/user/repos" \
        -H "Content-Type: application/json" \
        -u test:test123 \
        -d '{
            "name": "test-app",
            "description": "Claudernetes test application",
            "private": false,
            "auto_init": false
        }' 2>&1 > /dev/null
fi

sleep 2

# Initialize git repo with test app
echo_info "Initializing local git repository..."
TEMP_DIR=$(mktemp -d)
cp -r "$SCRIPT_DIR/test-app" "$TEMP_DIR/"
cd "$TEMP_DIR/test-app"

git init -b main
git config user.email "test@example.com"
git config user.name "Test User"
git add .
git status

echo_info "Committing test application files..."
git commit -m "Initial commit with claudernetes.md"

# Push to Gitea
echo_info "Pushing to Gitea..."
git remote add origin http://test:test123@localhost:3001/test/test-app.git
git push -u origin main --force

# Verify the push
echo_info "Verifying repository contents..."
TREE_RESPONSE=$(curl -s "http://localhost:3001/api/v1/repos/test/test-app/git/trees/main" -u test:test123)
if echo "$TREE_RESPONSE" | grep -q "claudernetes.md"; then
    echo_info "✓ claudernetes.md found in repository!"
else
    echo_error "✗ claudernetes.md NOT found in repository!"
    echo "$TREE_RESPONSE"
fi

# Cleanup
cd "$SCRIPT_DIR"
rm -rf "$TEMP_DIR"

echo ""
echo "======================================"
echo_info "Test Repository Created Successfully!"
echo "======================================"
echo ""
echo "Repository URL: http://localhost:3001/test/test-app"
echo "Gitea credentials: test / test123"
echo ""
echo "To access Gitea UI:"
echo "  kubectl port-forward -n git-server svc/gitea 3000:3000"
echo "  Then visit: http://localhost:3000"
echo ""
echo "======================================"
