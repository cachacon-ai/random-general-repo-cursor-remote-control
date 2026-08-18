# Pi + LM Studio + TelePi Setup (WSL on Windows)

Guide for running a **local coding agent** (Pi) against **Qwen 3.8 27B** in **LM Studio**, with **Telegram** access via **TelePi** — all from WSL while LM Studio runs on Windows.

Last updated: 2026-08-18

---

## Architecture

```text
Phone (Telegram)
    ↕  TelePi (WSL, systemd user service)
Pi coding agent (WSL)
    ↕  HTTP OpenAI-compatible API
LM Studio (Windows, GPU)
    ↕
Qwen 3.8 27B (local)
```

---

## Why not native Windows / curl install?

The `curl -fsSL https://pi.dev/install.sh | bash` path often fails on Windows/WSL because:

- **Linux Node** (Cursor/WSL) mixed with **Windows npm** (`/mnt/c/Program Files/nodejs/npm`) causes `Maximum call stack size exceeded`.
- **Pi** and **TelePi** should be installed in **WSL via Bun**, not Windows npm.

LM Studio stays on **Windows** (GPU). Pi + TelePi run in **WSL**.

---

## Prerequisites

- WSL2 (Ubuntu) with network access
- LM Studio installed on **Windows**
- Qwen 3.8 27B loaded in LM Studio
- Bun (installed automatically by setup script if missing)

---

## One-time install (WSL)

```bash
source ~/.bashrc
export PATH="$HOME/.bun/bin:$PATH"

# Automated setup (recommended)
~/repos/random-general-repo-cursor-remote-control/scripts/setup-pi-telepi-wsl.sh
```

Manual equivalent:

```bash
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc

bun install -g @earendil-works/pi-coding-agent
bun install -g @futurelab-studio/telepi

mkdir -p ~/.pi/agent/npm
cd ~/.pi/agent/npm && bun init -y && bun add pi-lmstudio
```

Verify:

```bash
pi --version      # expect 0.84.x
telepi version    # expect 0.4.x
pi list           # should show npm:pi-lmstudio
```

---

## Pi configuration files

| File | Purpose |
|------|---------|
| `~/.pi/agent/settings.json` | Use Bun for `pi install`; register packages |
| `~/.pi/agent/models.json` | LM Studio provider + Qwen model |
| `~/.pi/agent/lmstudio.json` | LM Studio URL(s) for pi-lmstudio extension |
| `~/.pi/agent/auth.json` | Dummy API key for local LM Studio |

### settings.json

```json
{
  "npmCommand": ["bun"],
  "packages": ["npm:pi-lmstudio"],
  "shellPath": "/bin/bash"
}
```

Using `"npmCommand": ["bun"]` avoids broken Windows npm when running `pi install`.

### models.json (example)

Replace `172.28.112.1` with your WSL→Windows gateway IP (`ip route show default | awk '{print $3}'`).

```json
{
  "providers": {
    "lmstudio": {
      "baseUrl": "http://172.28.112.1:1234/v1",
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
```

Model ID must match LM Studio exactly — check with:

```bash
curl http://172.28.112.1:1234/v1/models
```

### auth.json

```json
{
  "lmstudio": {
    "type": "api_key",
    "key": "lm-studio"
  }
}
```

---

## LM Studio on Windows

### Model settings (important for Qwen 3.8)

- **Context:** 32k minimum (not default 8k — thinking will consume it all)
- **Reasoning effort:** `medium` or `low` (default `xhigh` is extremely slow)
- **Keep model loaded** while using Pi

### Critical: WSL cannot reach 127.0.0.1 on Windows

By default LM Studio binds to **`127.0.0.1:1234`** (Windows localhost only). WSL is a separate network namespace and **cannot** connect until the server binds more broadly.

**Symptom:** LM Studio appears running; `curl` from WSL times out; Pi requests timeout.

**Verify from Windows PowerShell:**

```powershell
Get-NetTCPConnection -LocalPort 1234 | Select LocalAddress, State
# Bad for WSL:  LocalAddress = 127.0.0.1
# Good for WSL: LocalAddress = 0.0.0.0
```

### Fix A — Bind to all interfaces (what we used)

1. Edit `C:\Users\<you>\.lmstudio\.internal\http-server-config.json`:

```json
"networkInterface": "0.0.0.0"
```

2. Restart server:

```powershell
lms server stop
lms server start --bind 0.0.0.0
```

Or from WSL:

```bash
/mnt/c/Users/<you>/.lmstudio/bin/lms.exe server stop
/mnt/c/Users/<you>/.lmstudio/bin/lms.exe server start --bind 0.0.0.0
```

3. Test from WSL:

```bash
HOST=$(ip route show default | awk '{print $3}')
curl "http://${HOST}:1234/v1/models"
```

**Security:** `0.0.0.0` exposes the API on your LAN. Fine for home use; enable LM Studio auth on shared networks.

### Fix B — WSL mirrored networking (alternative)

Create `C:\Users\<you>\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Then `wsl --shutdown` and reopen WSL. LM Studio can stay on `127.0.0.1`; Pi uses `http://127.0.0.1:1234/v1` from WSL.

### After reboot

LM Studio GUI may restart the server on localhost only. Re-run:

```powershell
lms server start --bind 0.0.0.0
```

Or use the detect script:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/detect-lmstudio-host.sh
```

---

## Using Pi

### Detect LM Studio host

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/detect-lmstudio-host.sh
```

### List models

```bash
pi --list-models
# expect: lmstudio  qwen/qwen3.8-27b
```

### Smoke test

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/pi-smoke-test.sh
```

Or manually:

```bash
pi -p --provider lmstudio --model qwen/qwen3.8-27b --thinking low --no-tools "Reply exactly: pi-ok"
```

First response may take **30–90 seconds** on a 27B local model.

### Interactive session

```bash
cd ~/repos/random-general-repo-cursor-remote-control
pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium
```

Inside Pi: `/model` to switch models.

---

## TelePi (Telegram)

### Prerequisites

1. Bot token from [@BotFather](https://t.me/BotFather) (`/newbot`)
2. Your numeric Telegram user ID from [@userinfobot](https://t.me/userinfobot)
3. Pi working locally first (smoke test passes)

### Setup

```bash
telepi setup
```

Prompts for:

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_ALLOWED_USER_IDS` (comma-separated numeric IDs)
- `DEFAULT_WORKSPACE` → e.g. `/home/chris/repos/random-general-repo-cursor-remote-control`

Non-interactive:

```bash
telepi setup "YOUR_BOT_TOKEN" "YOUR_TELEGRAM_ID" "/home/chris/repos/random-general-repo-cursor-remote-control"
```

Config file: `~/.config/telepi/config.env`

Example template: `~/.config/telepi/config.env.example`

### Keep TelePi running after logout

```bash
loginctl enable-linger "$USER"
systemctl --user status telepi.service
systemctl --user restart telepi.service   # if needed
telepi status
```

### Daily workflow

1. Ensure LM Studio server is running (`lms server start --bind 0.0.0.0`)
2. Start Pi in your repo: `pi`
3. In Pi: `/handoff`
4. Open Telegram → your bot → `/start`
5. Send prompts from phone
6. `/handback` in Telegram to resume in terminal

---

## Helper scripts in this repo

| Script | Purpose |
|--------|---------|
| `scripts/setup-pi-telepi-wsl.sh` | Install Pi/TelePi, write config, detect LM Studio host |
| `scripts/detect-lmstudio-host.sh` | Find reachable LM Studio IP from WSL |
| `scripts/pi-smoke-test.sh` | curl + `pi --list-models` + one-shot prompt test |

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---------|--------------|-----|
| `curl` from WSL times out | LM Studio on `127.0.0.1` only | Bind `0.0.0.0` (see above) |
| Pi "Request timed out" | Server down, xhigh reasoning, or wrong IP | Start server, use `--thinking low`, check `baseUrl` |
| `pi install` stack overflow | Windows npm | `"npmCommand": ["bun"]` in settings.json |
| `pi` not found | PATH | `source ~/.bashrc` or `export PATH="$HOME/.bun/bin:$PATH"` |
| Gateway IP changed after reboot | WSL NAT | Re-run `detect-lmstudio-host.sh`, update `models.json` |
| Tools don't execute | Wrong API mode / model config | Try `openai-completions`; confirm tool-capable Qwen variant |
| TelePi bot silent | Service not running / wrong token | `telepi status`, check `config.env`, `/start` in Telegram |

---

## Harness comparison (why Pi?)

We evaluated several local agent stacks:

| Option | Verdict |
|--------|---------|
| **Pi + TelePi** | ✅ Chosen — proven with Qwen 3.8 27B; minimal harness; Telegram via TelePi |
| **Goose** | Built-in Telegram; more LM Studio + Qwen friction |
| **Oh My Pi** | Pi++ ; heavier; no public Qwen 3.8 27B reports |
| **OpenClaw** | Best for WhatsApp/iMessage; overkill for this stack |
| **OpenCode** | Good TUI; known LM Studio + Qwen tool-call issues |

---

## Quick reference commands

```bash
# PATH (every new WSL shell)
source ~/.bashrc

# LM Studio reachable?
curl http://$(ip route show default | awk '{print $3}'):1234/v1/models

# Pi one-liner test
pi -p --provider lmstudio --model qwen/qwen3.8-27b --thinking low --no-tools "say ok"

# TelePi status
telepi status
```
