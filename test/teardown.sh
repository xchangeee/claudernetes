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

echo_warn "This will delete the claudernetes-test kind cluster."
echo_warn "All test data will be lost. Continue? (y/n)"
read -r response

if [[ ! "$response" =~ ^[Yy]$ ]]; then
    echo_info "Cancelled."
    exit 0
fi

echo_info "Deleting kind cluster..."
kind delete cluster --name claudernetes-test

echo_info "Cleanup complete!"
