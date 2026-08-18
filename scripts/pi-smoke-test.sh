#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.bun/bin:$PATH"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="$("$SCRIPT_DIR/detect-lmstudio-host.sh")"

echo "LM Studio host: $HOST"
curl -sf "http://${HOST}:1234/v1/models" | head -c 400
echo
echo "--- Pi model list ---"
pi --list-models
echo "--- Pi prompt test (low thinking, no tools) ---"
pi -p --provider lmstudio --model qwen/qwen3.8-27b --thinking low --no-tools "Reply with exactly: pi-ok"
