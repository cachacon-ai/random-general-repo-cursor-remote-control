# Pi + LM Studio + Qwen 3.8 27B + TelePi (WSL Setup Guide)

This guide documents how to run a **local coding agent** on WSL using:

- **LM Studio** (Windows) — serves `qwen/qwen3.8-27b`
- **Pi** (WSL) — minimal agent harness
- **TelePi** (WSL) — Telegram bridge for phone access

Written for this machine: **Windows host + WSL2 Ubuntu**, user `chris`.

---

## Why not install on native Windows?

The official installer (`curl -fsSL https://pi.dev/install.sh | bash`) failed because this environment mixes:

- **Linux Node** (`~/.local/share/cursor-agent/.../node`)
- **Windows npm** (`/mnt/c/Program Files/nodejs/npm`)

That causes `npm` errors (`Maximum call stack size exceeded`) when Pi tries to install extensions.

**Fix:** Install and run Pi entirely in **WSL using Bun**.

---

## What's installed (WSL)

| Tool | Path | Version |
|------|------|---------|
| Bun | `~/.bun/bin/bun` | 1.3.14 |
| Pi | `~/.bun/bin/pi` | 0.84.2 (`@earendil-works/pi-coding-agent`) |
| pi-lmstudio | `~/.pi/agent/npm/node_modules/pi-lmstudio` | 1.5.0 |
| TelePi | `~/.bun/bin/telepi` | 0.4.2 (`@futurelab-studio/telepi`) |

Ensure PATH includes Bun (already in `~/.bashrc`):

```bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
```

Reinstall from scratch if needed:

```bash
bun install -g @earendil-works/pi-coding-agent
bun install -g @futurelab-studio/telepi
mkdir -p ~/.pi/agent/npm && cd ~/.pi/agent/npm && bun init -y && bun add pi-lmstudio
```

Or run the repo setup script:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/setup-pi-telepi-wsl.sh
```

---

## Config files (WSL)

| File | Purpose |
|------|---------|
| `~/.pi/agent/settings.json` | Pi settings; uses `"npmCommand": ["bun"]` |
| `~/.pi/agent/models.json` | LM Studio provider + Qwen model |
| `~/.pi/agent/lmstudio.json` | LM Studio URL(s) for pi-lmstudio extension |
| `~/.pi/agent/auth.json` | Dummy API key for local LM Studio |
| `~/.config/telepi/config.env` | TelePi bot token, user IDs, workspace (created by `telepi setup`) |
| `~/.config/telepi/config.env.example` | Template for TelePi config |

### Example `~/.pi/agent/settings.json`

```json
{
  "npmCommand": ["bun"],
  "packages": ["npm:pi-lmstudio"],
  "shellPath": "/bin/bash"
}
```

### Example `~/.pi/agent/models.json`

Replace `172.28.112.1` with your WSL gateway IP (see [Detect Windows host IP](#detect-windows-host-ip-from-wsl)).

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

> **Note:** Simon Willison's working setup used `"api": "openai-responses"`. If tool calling misbehaves, try switching to `openai-responses`. If requests hang, prefer `openai-completions`.

### Example `~/.pi/agent/auth.json`

```json
{
  "lmstudio": {
    "type": "api_key",
    "key": "lm-studio"
  }
}
```

---

## LM Studio (Windows)

### 1. Load the model

- Open **LM Studio** on Windows
- Load **`qwen/qwen3.8-27b`**
- Use a quant that fits your VRAM (e.g. Q4_K_M ~17GB)

### 2. Model settings (important)

- **Context length:** 32k minimum (not default 8k — Qwen thinking will consume 8k instantly)
- **Reasoning effort:** `medium` or `low` (default `xhigh` is extremely slow and burns tokens)

### 3. Start the server

Developer tab → **Start Server** (port 1234 by default).

Or via CLI:

```powershell
lms server start --bind 0.0.0.0
```

---

## Critical fix: WSL cannot reach `127.0.0.1` on Windows

By default, LM Studio binds to **`127.0.0.1:1234`** (Windows localhost only). WSL is a separate network namespace and **cannot** reach that address.

**Symptoms:**

- LM Studio appears running in the GUI
- `curl http://172.28.112.1:1234/v1/models` from WSL times out
- Pi `--list-models` may show cached model info but prompts time out

**Verify from Windows PowerShell:**

```powershell
Invoke-WebRequest http://127.0.0.1:1234/v1/models
Get-NetTCPConnection -LocalPort 1234 | Select LocalAddress, State
# If LocalAddress is 127.0.0.1 only → WSL cannot connect
```

### Fix A — Bind LM Studio to all interfaces (what we used)

Edit `C:\Users\cjfit\.lmstudio\.internal\http-server-config.json`:

```json
{
  "networkInterface": "0.0.0.0",
  "port": 1234
}
```

Restart the server:

```powershell
lms server stop
lms server start --bind 0.0.0.0
```

**Security:** `0.0.0.0` exposes the API on your LAN. Fine for home use; enable LM Studio authentication on shared networks.

### Fix B — WSL mirrored networking (alternative)

Create `C:\Users\cjfit\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Then from PowerShell: `wsl --shutdown`, reopen WSL.

With mirrored mode, WSL can reach Windows localhost via `127.0.0.1` and LM Studio can stay on localhost-only bind.

---

## Detect Windows host IP from WSL

```bash
ip route show default | awk '{print $3}'
# Example output: 172.28.112.1
```

Or use the repo helper:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/detect-lmstudio-host.sh
```

Test connectivity:

```bash
HOST=$(ip route show default | awk '{print $3}')
curl "http://${HOST}:1234/v1/models"
```

---

## Verify Pi + Qwen

```bash
source ~/.bashrc
export PATH="$HOME/.bun/bin:$PATH"

pi --version
pi list
pi --list-models
# Should show: lmstudio  qwen/qwen3.8-27b

# Quick non-interactive test (~30s first run)
cd ~/repos/random-general-repo-cursor-remote-control
pi -p --provider lmstudio --model qwen/qwen3.8-27b --thinking low --no-tools "Reply with exactly: pi-ok"
# Expected output: pi-ok
```

Or run the smoke-test script:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/pi-smoke-test.sh
```

### Interactive session

```bash
cd ~/repos/random-general-repo-cursor-remote-control
pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium
```

Inside Pi:

- `/model` — switch models
- `/help` — commands

---

## TelePi (Telegram from phone)

TelePi bridges Telegram ↔ Pi sessions on your PC.

### Prerequisites

1. Pi working locally (smoke test passes)
2. Telegram bot token from [@BotFather](https://t.me/BotFather) (`/newbot`)
3. Your numeric Telegram user ID from [@userinfobot](https://t.me/userinfobot)

### Setup

**Interactive:**

```bash
telepi setup
```

Prompts for:

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_ALLOWED_USER_IDS` (comma-separated numeric IDs)
- `DEFAULT_WORKSPACE` → e.g. `/home/chris/repos/random-general-repo-cursor-remote-control`

**Non-interactive:**

```bash
telepi setup "YOUR_BOT_TOKEN" "YOUR_TELEGRAM_ID" "/home/chris/repos/random-general-repo-cursor-remote-control"
```

Config is written to `~/.config/telepi/config.env`.

### Enable background service (Linux/WSL)

```bash
loginctl enable-linger "$USER"
systemctl --user status telepi.service
telepi status
```

### Daily usage

1. Start Pi in your repo: `pi`
2. Run `/handoff` inside Pi
3. Open Telegram → your bot → `/start`
4. Send prompts from your phone (text, voice, images supported)
5. `/handback` in Telegram to resume the same session in the terminal

### TelePi config template

See `~/.config/telepi/config.env.example`:

```env
TELEGRAM_BOT_TOKEN=replace-with-botfather-token
TELEGRAM_ALLOWED_USER_IDS=replace-with-your-numeric-telegram-id
DEFAULT_WORKSPACE=/home/chris/repos/random-general-repo-cursor-remote-control
```

---

## Repo helper scripts

| Script | Purpose |
|--------|---------|
| `scripts/setup-pi-telepi-wsl.sh` | Install/configure Pi + TelePi + LM Studio URLs |
| `scripts/detect-lmstudio-host.sh` | Find reachable LM Studio host IP from WSL |
| `scripts/pi-smoke-test.sh` | curl + `pi --list-models` + quick prompt test |

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---------|--------------|-----|
| `pi` not found | PATH | `source ~/.bashrc` or `export PATH="$HOME/.bun/bin:$PATH"` |
| `pi install` npm stack overflow | Windows npm in WSL | Use `"npmCommand": ["bun"]` in settings.json |
| WSL curl to :1234 times out | LM Studio on 127.0.0.1 only | Bind to `0.0.0.0` (see above) |
| Pi request timed out | LM Studio down, or xhigh reasoning | Start server; set reasoning to low/medium |
| Pi shows model but can't chat | Stale cache / wrong baseUrl | Update `models.json` baseUrl; verify curl works |
| First response very slow | 27B local model + thinking | Normal; expect 30s–3min depending on hardware |
| Gateway IP changed after reboot | WSL NAT | Re-run `detect-lmstudio-host.sh`; update models.json |
| TelePi bot doesn't respond | Service not running / wrong token | `telepi status`; check `config.env` |

---

## After reboot checklist

1. Start LM Studio on Windows; load Qwen 3.8 27B
2. Start server with network bind:
   ```powershell
   lms server start --bind 0.0.0.0
   ```
3. From WSL, verify:
   ```bash
   curl http://$(ip route show default | awk '{print $3}'):1234/v1/models
   ```
4. Check TelePi if using phone:
   ```bash
   telepi status
   ```

---

## Architecture

```
Phone (Telegram)
       ↕
   TelePi (WSL, systemd user service)
       ↕
   Pi agent (WSL)
       ↕  http://<windows-host-ip>:1234/v1
   LM Studio (Windows)
       ↕
   Qwen 3.8 27B (local GPU)
```

---

## Alternatives considered (for reference)

| Option | Verdict |
|--------|---------|
| **Cursor remote control** | Already working in this repo; different use case (Cursor cloud agent, not local Qwen) |
| **Goose + Telegram** | Built-in Telegram gateway; more LM Studio/Qwen friction |
| **Oh My Pi** | Pi++ with 32 tools; heavier on local 27B; no public Qwen 3.8 27B report |
| **OpenClaw** | Best for WhatsApp/multi-channel; overkill if Telegram + Pi suffices |
| **Vanilla Pi + TelePi** | **Chosen stack** — proven Qwen 3.8 27B + phone via Telegram |

---

## Quick reference commands

```bash
# PATH
export PATH="$HOME/.bun/bin:$PATH"

# LM Studio host
export LMSTUDIO_HOST=$(ip route show default | awk '{print $3}')

# Test LM Studio
curl "http://${LMSTUDIO_HOST}:1234/v1/models"

# Pi
pi --list-models
pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium

# TelePi
telepi setup
telepi status
```

---

## Windows-side LM Studio config path

```
C:\Users\cjfit\.lmstudio\.internal\http-server-config.json
C:\Users\cjfit\.lmstudio\bin\lms.exe
```
