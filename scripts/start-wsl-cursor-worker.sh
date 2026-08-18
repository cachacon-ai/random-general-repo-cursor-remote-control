#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"
REPO="$HOME/repos/random-general-repo-cursor-remote-control"

if ! command -v agent >/dev/null 2>&1; then
  echo "Cursor agent CLI not found. Run: curl https://cursor.com/install -fsS | bash"
  exit 1
fi

if ! agent status 2>/dev/null | grep -qi 'logged in'; then
  echo "Not logged in. Run: agent login"
  exit 1
fi

cd "$REPO"
echo "Starting Cursor worker for: $REPO"
exec agent worker start --worker-dir "$REPO" --name "strix-halo-wsl"
