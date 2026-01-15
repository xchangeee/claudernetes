#!/usr/bin/env python3
"""
Claudernetes - ArgoCD CMP for Claude-generated Kubernetes manifests
Reads claudernetes.md, calls Claude API, outputs K8s YAML
"""

import os
import sys
import json
import requests
from pathlib import Path


# System prompt to make Claude an expert K8s SRE
SYSTEM_PROMPT = """You are an expert Site Reliability Engineer and Kubernetes architect.

Your task is to generate production-ready Kubernetes manifests based on user instructions.

Requirements:
- Generate valid, idiomatic Kubernetes YAML
- Follow best practices (resource limits, security contexts, labels, etc.)
- Use appropriate API versions (apps/v1, v1, etc.)
- Include helpful comments explaining configuration choices
- Ensure manifests are deployable to a standard Kubernetes cluster
- Output ONLY valid YAML - no markdown code blocks, no explanations
- Multiple resources should be separated by '---'

Be concise but complete. Prioritize correctness and production-readiness."""


def read_instructions():
    """Read instructions from claudernetes.md in current directory."""
    instruction_file = Path("claudernetes.md")

    if not instruction_file.exists():
        print(f"Error: claudernetes.md not found in {Path.cwd()}", file=sys.stderr)
        sys.exit(1)

    try:
        with open(instruction_file, 'r') as f:
            content = f.read()
        return content
    except Exception as e:
        print(f"Error reading claudernetes.md: {e}", file=sys.stderr)
        sys.exit(1)


def read_api_key():
    """Read Anthropic API key from secret volume mount."""
    api_key_file = Path("/var/run/secrets/anthropic-api-key/api-key")

    if not api_key_file.exists():
        print("Error: API key not found at /var/run/secrets/anthropic-api-key/api-key",
              file=sys.stderr)
        sys.exit(1)

    try:
        with open(api_key_file, 'r') as f:
            api_key = f.read().strip()
        return api_key
    except Exception as e:
        print(f"Error reading API key: {e}", file=sys.stderr)
        sys.exit(1)


def call_claude_api(api_key, instructions):
    """Call Claude API to generate Kubernetes manifests."""
    url = "https://api.anthropic.com/v1/messages"

    headers = {
        "x-api-key": api_key,
        "anthropic-version": "2023-06-01",
        "content-type": "application/json"
    }

    payload = {
        "model": "claude-sonnet-4-5-20250929",
        "max_tokens": 4096,
        "system": SYSTEM_PROMPT,
        "messages": [
            {
                "role": "user",
                "content": instructions
            }
        ]
    }

    try:
        response = requests.post(url, headers=headers, json=payload, timeout=30)
        response.raise_for_status()

        result = response.json()

        # Extract text from response
        if "content" in result and len(result["content"]) > 0:
            manifest = result["content"][0]["text"]
            return manifest
        else:
            print(f"Error: Unexpected API response format: {result}", file=sys.stderr)
            sys.exit(1)

    except requests.exceptions.RequestException as e:
        print(f"Error calling Claude API: {e}", file=sys.stderr)
        if hasattr(e, 'response') and e.response is not None:
            print(f"Response: {e.response.text}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Unexpected error: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    """Main execution flow."""
    # Read instructions from repo
    instructions = read_instructions()

    # Read API key from secret
    api_key = read_api_key()

    # Call Claude API
    manifest = call_claude_api(api_key, instructions)

    # Output manifest to stdout (ArgoCD reads this)
    print(manifest)


if __name__ == "__main__":
    main()
