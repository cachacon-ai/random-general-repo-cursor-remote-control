# Pi + LM Studio + TelePi on WSL (Windows)

Guide for running a **local coding agent** on WSL with **Qwen 3.8 27B** in LM Studio (Windows) and **Telegram** access via TelePi.

---

## Recommended stack

```text
LM Studio (Windows) — Qwen 3.8 27B
        ↓
       Pi (WSL) — agent harness
        ↓
     TelePi (WSL) — Telegram bridge
```

**Why this stack:** Pi is the harness with the best documented success running Qwen 3.8 27B locally. TelePi adds phone access. Goose is a good fallback if Pi tool-calling is flaky (built-in Telegram, heavier harness).

**Why not native Windows for Pi:** This machine mixes Linux Node (Cursor agent) with Windows npm (`/mnt/c/Program Files/nodejs/npm`). That breaks `curl | bash` installs and `pi install`. Use **WSL + Bun** instead.

---

## Prerequisites

- **Windows** with LM Studio installed
- **WSL2** (Ubuntu) with Bun and Pi installed (see below)
- **Telegram** bot token from [@BotFather](https://t.me/BotFather) (for TelePi)
- **Telegram user ID** from [@userinfobot](https://t.me/userinfobot) (for TelePi allowlist)

---

## One-time install (WSL)

### Install Bun + Pi + TelePi

```bash
# Bun (if missing)
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc
export PATH="$HOME/.bun/bin:$PATH"

# Pi coding agent
bun install -g @earendil-works/pi-coding-agent

# pi-lmstudio extension (use bun — NOT Windows npm)
mkdir -p ~/.pi/agent/npm
cd ~/.pi/agent/npm && bun init -y && bun add pi-lmstudio

# TelePi
bun install -g @futurelab-studio/telepi
```

Or run the repo setup script:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/setup-pi-telepi-wsl.sh
```

### Verify

```bash
pi --version      # expect 0.84.x
telepi version    # expect 0.4.x
pi list           # should show npm:pi-lmstudio
```

---

## Pi configuration files

| File | Purpose |
|------|---------|
| `~/.pi/agent/settings.json` | Packages, use `bun` for `pi install` |
| `~/.pi/agent/models.json` | LM Studio provider + Qwen model |
| `~/.pi/agent/lmstudio.json` | LM Studio URL(s) for pi-lmstudio |
| `~/.pi/agent/auth.json` | Dummy API key for local LM Studio |
| `~/.config/telepi/config.env` | TelePi bot token + allowlist (after setup) |

### `~/.pi/agent/settings.json`

```json
{
  "npmCommand": ["bun"],
  "packages": ["npm:pi-lmstudio"],
  "shellPath": "/bin/bash"
}
```

Using `"npmCommand": ["bun"]` avoids the broken Windows npm path when running `pi install`.

### `~/.pi/agent/models.json`

Replace `172.28.112.1` with your WSL gateway IP if it changes (`ip route show default | awk '{print $3}'`).

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

Model ID must match LM Studio exactly. Check with:

```bash
curl "http://$(ip route show default | awk '{print $3}'):1234/v1/models"
```

### `~/.pi/agent/auth.json`

```json
{
  "lmstudio": {
    "type": "api_key",
    "key": "lm-studio"
  }
}
```

### `~/.pi/agent/lmstudio.json`

```json
{
  "urls": [
    { "name": "windows", "url": "http://172.28.112.1:1234" },
    { "name": "local", "url": "http://127.0.0.1:1234" }
  ]
}
```

---

## LM Studio (Windows)

### Model settings

1. Load **qwen/qwen3.8-27b**
2. **Developer tab → Start Server**
3. **Context:** 32k minimum (not 8k — Qwen thinking burns context fast)
4. **Reasoning effort:** **medium** or **low** (default `xhigh` is extremely slow)

### Critical: WSL cannot reach `127.0.0.1` on Windows

By default LM Studio binds to **localhost only** (`127.0.0.1`). WSL is a separate network namespace and **cannot** connect until the server listens on all interfaces.

**Symptom:** LM Studio appears running; `curl` from WSL times out; Pi requests timeout.

**Verify from Windows (PowerShell):**

```powershell
Get-NetTCPConnection -LocalPort 1234 | Select LocalAddress, State
# Bad for WSL:  LocalAddress = 127.0.0.1
# Good for WSL:  LocalAddress = 0.0.0.0
```

**Fix A — Config file (persistent):**

Edit `C:\Users\cjfit\.lmstudio\.internal\http-server-config.json`:

```json
"networkInterface": "0.0.0.0"
```

Then restart the server:

```powershell
lms server stop
lms server start --bind 0.0.0.0
```

**Fix B — CLI only:**

```powershell
lms server stop
lms server start --bind 0.0.0.0
```

**Fix C — WSL mirrored networking (keeps LM Studio on localhost):**

Create `C:\Users\cjfit\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Then run `wsl --shutdown` and reopen WSL. Pi can then use `http://127.0.0.1:1234/v1`.

**Security:** `0.0.0.0` exposes the API on your LAN. Fine for home use; enable LM Studio authentication on shared networks.

### Test connectivity from WSL

```bash
HOST=$(ip route show default | awk '{print $3}')
echo "Gateway: $HOST"
curl "http://${HOST}:1234/v1/models"
```

Or use the repo script:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/detect-lmstudio-host.sh
```

---

## Using Pi

### List models

```bash
export PATH="$HOME/.bun/bin:$PATH"
pi --list-models
```

Expected:

```text
provider  model             context  ...
lmstudio  qwen/qwen3.8-27b  128K     ...
```

### Smoke test (non-interactive)

```bash
cd ~/repos/random-general-repo-cursor-remote-control
pi -p --provider lmstudio --model qwen/qwen3.8-27b --thinking low --no-tools "Reply with exactly: pi-ok"
```

Or:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/pi-smoke-test.sh
```

First response may take **30–90 seconds** on a 27B model.

### Interactive session

```bash
cd ~/repos/random-general-repo-cursor-remote-control
pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium
```

Inside Pi:

- `/model` — switch models
- `/handoff` — hand session to TelePi (after TelePi is set up)

---

## TelePi (Telegram)

### 1. Create bot

1. Message [@BotFather](https://t.me/BotFather) → `/newbot`
2. Save the **bot token**

### 2. Get your Telegram user ID

1. Message [@userinfobot](https://t.me/userinfobot)
2. Save your **numeric ID**

### 3. Run setup (WSL)

Interactive:

```bash
telepi setup
```

Non-interactive:

```bash
telepi setup "YOUR_BOT_TOKEN" "YOUR_TELEGRAM_ID" "/home/chris/repos/random-general-repo-cursor-remote-control"
```

Config is written to `~/.config/telepi/config.env`:

```bash
TELEGRAM_BOT_TOKEN=...
TELEGRAM_ALLOWED_USER_IDS=...
DEFAULT_WORKSPACE=/home/chris/repos/random-general-repo-cursor-remote-control
```

Example template: `~/.config/telepi/config.env.example`

### 4. Keep TelePi running after logout

```bash
loginctl enable-linger "$USER"
systemctl --user status telepi.service
telepi status
```

### 5. Daily workflow

1. Start LM Studio server on Windows (with `0.0.0.0` bind if using NAT WSL)
2. In WSL: `cd ~/repos/random-general-repo-cursor-remote-control && pi`
3. In Pi: `/handoff`
4. On phone: open Telegram bot → `/start` → send prompts
5. When back at desk: `/handback` in Telegram to resume in terminal

---

## Repo helper scripts

| Script | Purpose |
|--------|---------|
| `scripts/setup-pi-telepi-wsl.sh` | Install/configure Pi + TelePi + write config |
| `scripts/detect-lmstudio-host.sh` | Find reachable LM Studio host IP from WSL |
| `scripts/pi-smoke-test.sh` | Test LM Studio + Pi end-to-end |

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---------|--------------|-----|
| `curl` from WSL times out | LM Studio on `127.0.0.1` only | Bind `0.0.0.0` (see above) |
| Pi request timeout | LM Studio down or xhigh reasoning | Start server; set medium/low reasoning |
| `pi install` stack overflow | Windows npm in WSL PATH | Use `"npmCommand": ["bun"]` in settings.json |
| Empty tool calls / no execution | Wrong API mode or context too small | Try `openai-completions`; set 32k+ context |
| Gateway IP changed after reboot | WSL NAT | Re-run `detect-lmstudio-host.sh`; update `models.json` |
| `pi` not found | PATH | `source ~/.bashrc` or `export PATH="$HOME/.bun/bin:$PATH"` |

---

## Alternatives considered

| Tool | Role | Notes |
|------|------|-------|
| **Goose** | Agent + built-in Telegram | Easier phone setup; more LM Studio/Qwen friction |
| **Oh My Pi** | Pi++ with 32 tools, LSP | Heavier; no public Qwen 3.8 27B report; try after Pi works |
| **OpenClaw** | Personal assistant + messaging | WhatsApp/iMessage; not Qwen-focused |
| **OpenCode** | Terminal coding agent | Good TUI; known LM Studio + Qwen tool-call issues |
| **Cursor remote** | Cloud/private worker | Different use case (Cursor agents, not local Qwen) |

---

## After reboot checklist

1. Start LM Studio on Windows; load Qwen 3.8 27B
2. `lms server start --bind 0.0.0.0` (if not using mirrored WSL)
3. From WSL: `curl http://$(ip route show default | awk '{print $3}'):1234/v1/models`
4. `telepi status` (TelePi should auto-start if systemd user service enabled)
5. `pi` in your repo and go

---

## Paths quick reference

```text
Windows LM Studio config:  C:\Users\cjfit\.lmstudio\.internal\http-server-config.json
WSL Pi config:             ~/.pi/agent/
WSL TelePi config:         ~/.config/telepi/config.env
WSL Bun/Pi binaries:       ~/.bun/bin/pi  ~/.bun/bin/telepi
This repo:                 ~/repos/random-general-repo-cursor-remote-control
```
