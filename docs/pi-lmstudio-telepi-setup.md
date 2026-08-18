# Pi + LM Studio + TelePi Setup (WSL on Windows)

Guide for running a **local Qwen 3.8 27B** agent via **Pi**, served by **LM Studio on Windows**, with **TelePi** for Telegram access from your phone.

This repo also contains helper scripts under `scripts/`.

---

## Architecture

```text
Phone (Telegram)
    ↕ TelePi (WSL, always-on service)
    ↕ Pi coding agent (WSL)
    ↕ LM Studio API (Windows, port 1234)
    ↕ Qwen 3.8 27B (local GPU/RAM)
```

- **LM Studio** runs on **Windows** (GPU access).
- **Pi + TelePi** run in **WSL** (Linux).
- Do **not** use the Windows `curl | bash` Pi installer — it breaks when WSL mixes Linux Node with Windows npm.

---

## Why Windows `curl | bash` failed

| Problem | Cause |
|---------|-------|
| `pi.dev/install.sh` fails | Script often returns 500; use Bun/npm in WSL instead |
| `pi install npm:pi-lmstudio` fails | WSL was calling **Windows npm** (`/mnt/c/Program Files/nodejs/npm`) while using Linux Node |
| LM Studio unreachable from WSL | Server was bound to `127.0.0.1` only (Windows localhost) |

**Fix:** Install with **Bun in WSL**, configure Pi to use `npmCommand: ["bun"]`, and bind LM Studio to `0.0.0.0`.

---

## Installed components (WSL)

| Tool | Path | Notes |
|------|------|-------|
| Bun | `~/.bun/bin/bun` | Package manager / runtime |
| Pi | `~/.bun/bin/pi` | `@earendil-works/pi-coding-agent` |
| pi-lmstudio | `~/.pi/agent/npm/node_modules/pi-lmstudio` | LM Studio provider extension |
| TelePi | `~/.bun/bin/telepi` | `@futurelab-studio/telepi` |

Ensure PATH includes Bun (already in `~/.bashrc`):

```bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
```

---

## Fresh install (WSL)

Run the repo setup script:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/setup-pi-telepi-wsl.sh
```

Or manually:

```bash
# Install Bun (if needed)
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc

# Install Pi and TelePi
bun install -g @earendil-works/pi-coding-agent
bun install -g @futurelab-studio/telepi

# Install pi-lmstudio extension
mkdir -p ~/.pi/agent/npm
cd ~/.pi/agent/npm && bun init -y && bun add pi-lmstudio
```

Create `~/.pi/agent/settings.json`:

```json
{
  "npmCommand": ["bun"],
  "packages": ["npm:pi-lmstudio"],
  "shellPath": "/bin/bash"
}
```

---

## LM Studio (Windows)

### 1. Load the model

1. Open **LM Studio** on Windows.
2. Load **qwen/qwen3.8-27b** (or your preferred Qwen 3.8 quant).
3. Recommended settings:
   - **Context:** 32k minimum (not 8k — Qwen thinking will consume it instantly)
   - **Reasoning effort:** `medium` or `low` (not `xhigh` — extremely slow and token-heavy)

### 2. Start the server

**Critical for WSL:** The server must listen beyond Windows localhost.

#### Option A — Config file (persistent)

Edit `C:\Users\cjfit\.lmstudio\.internal\http-server-config.json`:

```json
{
  "networkInterface": "0.0.0.0",
  "port": 1234
}
```

Then restart the server from LM Studio or CLI.

#### Option B — CLI

```powershell
lms server stop
lms server start --bind 0.0.0.0
```

(`lms.exe` is at `C:\Users\cjfit\.lmstudio\bin\lms.exe`)

### 3. Verify from WSL

```bash
# Detect Windows host IP from WSL
~/repos/random-general-repo-cursor-remote-control/scripts/detect-lmstudio-host.sh

# Usually the default gateway:
curl http://172.28.112.1:1234/v1/models
```

You should see `qwen/qwen3.8-27b` in the JSON response.

### 4. Security note

Binding to `0.0.0.0` exposes the API on your LAN. Fine for home use; enable LM Studio authentication on shared networks.

### Alternative: WSL mirrored networking

If you prefer LM Studio to stay on `127.0.0.1`, create `C:\Users\cjfit\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Then run `wsl --shutdown` and reopen WSL. Pi can then use `http://127.0.0.1:1234/v1`.

---

## Pi configuration

### Config files

| File | Purpose |
|------|---------|
| `~/.pi/agent/settings.json` | Bun as package manager, pi-lmstudio package |
| `~/.pi/agent/models.json` | LM Studio provider + Qwen model |
| `~/.pi/agent/lmstudio.json` | LM Studio server URLs |
| `~/.pi/agent/auth.json` | Dummy API key for local LM Studio |

### Example `models.json`

Replace `172.28.112.1` with your WSL gateway IP (from `detect-lmstudio-host.sh`):

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

### Example `auth.json`

```json
{
  "lmstudio": {
    "type": "api_key",
    "key": "lm-studio"
  }
}
```

### Example `lmstudio.json`

```json
{
  "urls": [
    { "name": "windows", "url": "http://172.28.112.1:1234" },
    { "name": "local", "url": "http://127.0.0.1:1234" }
  ]
}
```

---

## Smoke test

```bash
source ~/.bashrc
cd ~/repos/random-general-repo-cursor-remote-control

# List models
pi --list-models

# One-shot test (expect ~30s on first run for 27B)
pi -p --provider lmstudio --model qwen/qwen3.8-27b --thinking low --no-tools "Reply with exactly: pi-ok"

# Or use the script
~/repos/random-general-repo-cursor-remote-control/scripts/pi-smoke-test.sh
```

Expected output: `pi-ok`

### Interactive session

```bash
cd ~/repos/random-general-repo-cursor-remote-control
pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium
```

Inside Pi:
- `/model` — switch models
- Ask it to read files, run bash, edit code

---

## TelePi (Telegram from phone)

### Prerequisites

- Pi working locally (smoke test passes)
- Node 22.19+ (or 20+ for TelePi) in WSL
- Telegram bot token from [@BotFather](https://t.me/BotFather)
- Your numeric Telegram user ID from [@userinfobot](https://t.me/userinfobot)

### Setup

**Interactive:**

```bash
telepi setup
```

Prompts for:
1. `TELEGRAM_BOT_TOKEN`
2. `TELEGRAM_ALLOWED_USER_IDS` (comma-separated numeric IDs)
3. `DEFAULT_WORKSPACE` → `/home/chris/repos/random-general-repo-cursor-remote-control`

**Non-interactive:**

```bash
telepi setup "YOUR_BOT_TOKEN" "YOUR_TELEGRAM_ID" "/home/chris/repos/random-general-repo-cursor-remote-control"
```

Config is saved to `~/.config/telepi/config.env`.

Example template: `~/.config/telepi/config.env.example`

### Enable background service (Linux/WSL)

```bash
loginctl enable-linger "$USER"
telepi status
systemctl --user status telepi.service
```

### Daily usage

1. Start LM Studio server on Windows (with `0.0.0.0` bind).
2. In WSL, open Pi in your repo:
   ```bash
   cd ~/repos/random-general-repo-cursor-remote-control
   pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium
   ```
3. Inside Pi, run `/handoff`.
4. Open Telegram → your bot → `/start`.
5. Send prompts from your phone.
6. Run `/handback` in Telegram to resume in the terminal.

### TelePi commands (Telegram)

- `/start` — initialize bot
- `/handback` — return session to terminal
- `/model` — switch model
- `/help` — usage

---

## After reboot / troubleshooting

### LM Studio not reachable from WSL

**Symptom:** `curl http://172.28.112.1:1234/v1/models` times out.

**Check from Windows PowerShell:**

```powershell
Invoke-WebRequest http://127.0.0.1:1234/v1/models
Get-NetTCPConnection -LocalPort 1234 | Select LocalAddress, State
```

If `LocalAddress` is `127.0.0.1` only → re-bind:

```powershell
lms server stop
lms server start --bind 0.0.0.0
```

### Pi request timeout

- Confirm LM Studio server is running and reachable from WSL.
- Lower reasoning: `--thinking low`.
- Increase context in LM Studio (32k+).
- First 27B inference can take 1–3 minutes.

### WSL gateway IP changed

Re-run:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/detect-lmstudio-host.sh
```

Update `baseUrl` in `~/.pi/agent/models.json`.

### `pi install` fails with npm stack overflow

Ensure `~/.pi/agent/settings.json` has:

```json
"npmCommand": ["bun"]
```

---

## Helper scripts in this repo

| Script | Purpose |
|--------|---------|
| `scripts/setup-pi-telepi-wsl.sh` | Full WSL install + config |
| `scripts/detect-lmstudio-host.sh` | Find reachable LM Studio host IP |
| `scripts/pi-smoke-test.sh` | Test LM Studio + Pi end-to-end |
| `scripts/start-wsl-cursor-worker.sh` | Cursor remote control worker (separate) |

---

## Harness comparison (why Pi?)

We evaluated several local agent stacks:

| Harness | Qwen 3.8 27B | Telegram | Verdict |
|---------|--------------|----------|---------|
| **Pi** | ✅ Proven (Simon Willison, smoke test) | Via TelePi | **Chosen stack** |
| Goose | ⚠️ LM Studio/Qwen quirks | Built-in | Backup if Pi fails |
| Oh My Pi | ❓ Unproven for 3.8 27B | Via extensions | Upgrade later if Pi feels too minimal |
| OpenClaw | Good for messaging | Built-in | Overkill for this use case |
| OpenCode | ⚠️ Tool-call issues with LM Studio+Qwen | DIY | Not recommended for local Qwen |

---

## Quick reference commands

```bash
# PATH
source ~/.bashrc

# Versions
pi --version
telepi version

# LM Studio from WSL
curl http://172.28.112.1:1234/v1/models

# Pi one-shot
pi -p --provider lmstudio --model qwen/qwen3.8-27b --thinking low "hello"

# Pi interactive
pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium

# TelePi
telepi setup
telepi status
```

---

## Windows-side LM Studio restart (after reboot)

```powershell
# PowerShell on Windows
C:\Users\cjfit\.lmstudio\bin\lms.exe server stop
C:\Users\cjfit\.lmstudio\bin\lms.exe server start --bind 0.0.0.0
```

Or open LM Studio → Developer tab → Start Server (with `networkInterface: 0.0.0.0` in config).
