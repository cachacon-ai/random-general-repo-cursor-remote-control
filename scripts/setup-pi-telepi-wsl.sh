#!/usr/bin/env bash
set -euo pipefail

export PATH="$HOME/.bun/bin:$PATH"

if ! command -v bun >/dev/null 2>&1; then
  curl -fsSL https://bun.sh/install | bash
  export PATH="$HOME/.bun/bin:$PATH"
fi

if ! command -v pi >/dev/null 2>&1; then
  echo "Installing Pi coding agent..."
  bun install -g @earendil-works/pi-coding-agent
fi

mkdir -p "$HOME/.pi/agent"

if [[ ! -f "$HOME/.pi/agent/settings.json" ]]; then
  cat >"$HOME/.pi/agent/settings.json" <<'EOF'
{
  "npmCommand": ["bun"],
  "packages": ["npm:pi-lmstudio"],
  "shellPath": "/bin/bash"
}
EOF
fi

if ! grep -q '"npm:pi-lmstudio"' "$HOME/.pi/agent/settings.json" 2>/dev/null; then
  echo "Add npm:pi-lmstudio to ~/.pi/agent/settings.json packages manually."
fi

if [[ ! -d "$HOME/.pi/agent/npm/node_modules/pi-lmstudio" ]]; then
  echo "Installing pi-lmstudio extension with bun..."
  mkdir -p "$HOME/.pi/agent/npm"
  (cd "$HOME/.pi/agent/npm" && bun init -y >/dev/null 2>&1 && bun add pi-lmstudio)
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOST="$("$SCRIPT_DIR/detect-lmstudio-host.sh" || true)"
if [[ -z "${HOST:-}" ]]; then
  echo "WARNING: LM Studio not reachable on port 1234."
  echo "Start LM Studio on Windows -> Developer tab -> Start Server."
  echo "Enable 'Serve on local network' if WSL cannot connect."
  HOST="$(ip route show default | awk '{print $3}' | head -1)"
fi

cat >"$HOME/.pi/agent/lmstudio.json" <<EOF
{
  "urls": [
    { "name": "windows", "url": "http://${HOST}:1234" },
    { "name": "local", "url": "http://127.0.0.1:1234" }
  ]
}
EOF

cat >"$HOME/.pi/agent/models.json" <<EOF
{
  "providers": {
    "lmstudio": {
      "baseUrl": "http://${HOST}:1234/v1",
      "api": "openai-completions",
      "apiKey": "lm-studio",
      "models": [
        {
          "id": "qwen/qwen3.8-27b",
          "name": "Qwen 3.8 27B (local)",
          "reasoning": true,
          "input": ["text", "image"],
          "compat": {
            "thinkingFormat": "openai",
            "supportsReasoningEffort": true
          }
        }
      ]
    }
  }
}
EOF

cat >"$HOME/.pi/agent/auth.json" <<'EOF'
{
  "lmstudio": {
    "type": "api_key",
    "key": "lm-studio"
  }
}
EOF

if ! command -v telepi >/dev/null 2>&1; then
  echo "Installing TelePi..."
  bun install -g @futurelab-studio/telepi
fi

mkdir -p "$HOME/.config/telepi"
if [[ ! -f "$HOME/.config/telepi/config.env" ]]; then
  cat >"$HOME/.config/telepi/config.env.example" <<'EOF'
TELEGRAM_BOT_TOKEN=replace-with-botfather-token
TELEGRAM_ALLOWED_USER_IDS=replace-with-your-numeric-telegram-id
DEFAULT_WORKSPACE=/home/chris/repos/random-general-repo-cursor-remote-control
EOF
  echo "Created ~/.config/telepi/config.env.example"
  echo "Run: telepi setup   (interactive) after LM Studio + Pi work."
fi

echo
echo "Pi: $(pi --version)"
echo "TelePi: $(telepi version 2>/dev/null || echo installed)"
echo "LM Studio host: http://${HOST}:1234"
echo
echo "Next:"
echo "  1) Start LM Studio server on Windows with qwen3.8-27b loaded"
echo "  2) pi --list-models"
echo "  3) pi -p --provider lmstudio --model qwen/qwen3.8-27b --thinking low 'say ok'"
echo "  4) telepi setup"
