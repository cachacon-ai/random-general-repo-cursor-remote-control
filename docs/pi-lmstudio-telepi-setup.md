# Pi + LM Studio + Qwen 3.8 27B + TelePi (WSL on Windows)

Guide for running a **local coding agent** on WSL, powered by **Qwen 3.8 27B** in **LM Studio** on Windows, with **Telegram** access via **TelePi**.

Last updated: 2026-08-18

---

## Architecture

```text
Phone (Telegram)
    ↕ TelePi (WSL, always-on service)
    ↕ Pi coding agent (WSL)
    ↕ LM Studio API (Windows, port 1234)
    ↕ Qwen 3.8 27B (local GPU/RAM)
```

- **LM Studio** runs on **Windows** (GUI + model server).
- **Pi** and **TelePi** run in **WSL** (Ubuntu).
- WSL reaches Windows LM Studio via the **WSL gateway IP** (not `127.0.0.1` unless mirrored networking is enabled).

---

## Why not install Pi on native Windows?

The `curl -fsSL https://pi.dev/install.sh | bash` path often fails on Windows/WSL hybrid setups because:

- **Linux Node** may be used while **Windows npm** (`/mnt/c/Program Files/nodejs/npm`) handles package installs.
- That mismatch causes errors like `Maximum call stack size exceeded` when running `pi install`.

**Recommended:** Install Pi in **WSL using Bun**, not Windows npm.

---

## Prerequisites

| Requirement | Notes |
|-------------|-------|
| WSL2 (Ubuntu) | Where Pi and TelePi run |
| LM Studio (Windows) | Serves Qwen 3.8 27B |
| Bun | Package manager for Pi/TelePi in WSL |
| Telegram bot token | From [@BotFather](https://t.me/BotFather) |
| Your Telegram user ID | From [@userinfobot](https://t.me/userinfobot) |

---

## One-shot setup (WSL)

From the repo root:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/setup-pi-telepi-wsl.sh
```

This script:

- Installs **Bun** (if missing)
- Installs **Pi** (`@earendil-works/pi-coding-agent`)
- Installs **pi-lmstudio** extension
- Writes `~/.pi/agent/models.json`, `lmstudio.json`, `auth.json`, `settings.json`
- Installs **TelePi** (`@futurelab-studio/telepi`)
- Creates `~/.config/telepi/config.env.example`

Ensure Bun/Pi are on PATH (already in `~/.bashrc`):

```bash
source ~/.bashrc
export PATH="$HOME/.bun/bin:$PATH"
```

---

## Manual install (if you prefer)

### 1. Install Bun + Pi + TelePi

```bash
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc

bun install -g @earendil-works/pi-coding-agent
bun install -g @futurelab-studio/telepi

pi --version    # expect 0.84.x
telepi version  # expect 0.4.x
```

### 2. Install pi-lmstudio extension

Pi's `pi install npm:pi-lmstudio` uses npm and may fail with Windows npm. Use Bun instead:

```bash
mkdir -p ~/.pi/agent/npm
cd ~/.pi/agent/npm
bun init -y
bun add pi-lmstudio
```

Register in `~/.pi/agent/settings.json`:

```json
{
  "npmCommand": ["bun"],
  "packages": ["npm:pi-lmstudio"],
  "shellPath": "/bin/bash"
}
```

### 3. Pi config files

**`~/.pi/agent/settings.json`** — use Bun for package installs (see above).

**`~/.pi/agent/auth.json`** — dummy key for local LM Studio:

```json
{
  "lmstudio": {
    "type": "api_key",
    "key": "lm-studio"
  }
}
```

**`~/.pi/agent/lmstudio.json`** — WSL host detection:

```json
{
  "urls": [
    { "name": "windows", "url": "http://172.28.112.1:1234" },
    { "name": "local", "url": "http://127.0.0.1:1234" }
  ]
}
```

Replace `172.28.112.1` with your current WSL gateway IP:

```bash
ip route show default | awk '{print $3}'
# or
~/repos/random-general-repo-cursor-remote-control/scripts/detect-lmstudio-host.sh
```

**`~/.pi/agent/models.json`** — Qwen 3.8 27B provider:

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

Use the exact model `id` from:

```bash
curl http://172.28.112.1:1234/v1/models
```

---

## LM Studio on Windows

### Load the model

1. Open **LM Studio** on Windows.
2. Load **qwen/qwen3.8-27b**.
3. Set **context to 32k+** (not 8192 — Qwen thinking will consume 8k instantly).
4. Set **reasoning effort to medium or low** (default `xhigh` is extremely slow).

### Start the server

**Developer tab → Start Server** (port 1234).

### Critical: WSL cannot reach `127.0.0.1` on Windows by default

LM Studio defaults to binding **localhost only** (`127.0.0.1`). WSL will **timeout** even when the server appears running in the GUI.

**Verify from Windows (PowerShell):**

```powershell
Invoke-WebRequest http://127.0.0.1:1234/v1/models
Get-NetTCPConnection -LocalPort 1234 | Select LocalAddress, State
# If LocalAddress is 127.0.0.1 only → WSL cannot connect
```

**Fix A — Bind to all interfaces (recommended for NAT WSL):**

Edit `C:\Users\<you>\.lmstudio\.internal\http-server-config.json`:

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

**Fix B — WSL mirrored networking (keeps LM Studio on localhost):**

Create `C:\Users\<you>\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Then from PowerShell: `wsl --shutdown`, reopen WSL. Pi can then use `http://127.0.0.1:1234/v1`.

### Verify from WSL

```bash
HOST=$(ip route show default | awk '{print $3}')
curl "http://${HOST}:1234/v1/models"
```

You should see `qwen/qwen3.8-27b` in the response.

---

## Pi smoke test

```bash
export PATH="$HOME/.bun/bin:$PATH"
cd ~/repos/random-general-repo-cursor-remote-control

pi --list-models
# expect: lmstudio  qwen/qwen3.8-27b

pi -p --provider lmstudio --model qwen/qwen3.8-27b --thinking low --no-tools "Reply exactly: pi-ok"
# expect: pi-ok (may take 30–90s on first run)
```

Or use the repo script:

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

### 1. Create Telegram bot

1. Message [@BotFather](https://t.me/BotFather) → `/newbot`
2. Save the **bot token**

### 2. Get your Telegram user ID

1. Message [@userinfobot](https://t.me/userinfobot)
2. Save your **numeric ID**

### 3. Run TelePi setup (WSL)

**Interactive:**

```bash
telepi setup
```

**Non-interactive:**

```bash
telepi setup "YOUR_BOT_TOKEN" "YOUR_TELEGRAM_ID" "/home/chris/repos/random-general-repo-cursor-remote-control"
```

Config is written to `~/.config/telepi/config.env`:

```bash
TELEGRAM_BOT_TOKEN=...
TELEGRAM_ALLOWED_USER_IDS=123456789
DEFAULT_WORKSPACE=/home/chris/repos/random-general-repo-cursor-remote-control
```

### 4. Keep TelePi running after logout

```bash
loginctl enable-linger "$USER"
systemctl --user status telepi.service
systemctl --user restart telepi.service   # if needed
```

### 5. Daily usage

1. Start Pi in your repo: `pi`
2. In Pi, run: `/handoff`
3. Open Telegram → your bot → `/start`
4. Send prompts from your phone (text, voice, images supported)
5. Run `/handback` in Telegram to resume the same session in the terminal

**Check status:**

```bash
telepi status
```

---

## Repo scripts reference

| Script | Purpose |
|--------|---------|
| `scripts/setup-pi-telepi-wsl.sh` | Full WSL install + config |
| `scripts/detect-lmstudio-host.sh` | Find reachable LM Studio IP from WSL |
| `scripts/pi-smoke-test.sh` | Test LM Studio + Pi end-to-end |
| `scripts/start-wsl-cursor-worker.sh` | Cursor remote-control worker (separate) |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `curl` to `:1234` times out from WSL | LM Studio bound to `127.0.0.1` only | Bind `0.0.0.0` (see above) |
| Pi `Request timed out` | LM Studio down, xhigh reasoning, or wrong IP | Start server; use `--thinking low`; fix `baseUrl` |
| `pi install` stack overflow | Windows npm in WSL | Use `"npmCommand": ["bun"]` in settings.json |
| `pi` command not found | PATH | `source ~/.bashrc` or `export PATH="$HOME/.bun/bin:$PATH"` |
| Model id mismatch | Wrong id in models.json | Match id from `/v1/models` exactly |
| TelePi bot silent | Service not running / wrong token | `telepi status`; re-run `telepi setup` |
| Gateway IP changed after reboot | WSL NAT | Re-run `detect-lmstudio-host.sh`; update models.json |

---

## Security notes

- **TelePi allowlist:** Only your Telegram user ID should be in `TELEGRAM_ALLOWED_USER_IDS`.
- **LM Studio on `0.0.0.0`:** Exposes the API to your LAN. Enable LM Studio authentication on shared networks.
- **Pi tools:** The agent can run shell commands and edit files — treat Telegram access like remote code execution.

---

## Harness choice (context)

This setup uses **Pi** (minimal harness) + **TelePi** because:

- **Qwen 3.8 27B + Pi** is documented/working (Simon Willison et al.).
- **Telegram** via TelePi is simpler than wiring Goose/OpenClaw for this stack.
- **Oh My Pi** and **Goose** are alternatives if Pi feels too minimal or Telegram setup is too fiddly.

See conversation history in the repo/agent notes for comparisons.

---

## After reboot checklist

1. Start **LM Studio** on Windows, load Qwen 3.8 27B.
2. Start server with network bind:
   ```powershell
   lms server start --bind 0.0.0.0
   ```
3. From WSL: `curl http://$(ip route | awk '/default/{print $3}'):1234/v1/models`
4. Update `~/.pi/agent/models.json` if gateway IP changed.
5. Confirm TelePi: `telepi status` (systemd user service should auto-start if configured).

---

## Installed versions (2026-08-18)

| Component | Version | Path |
|-----------|---------|------|
| Pi | 0.84.2 | `~/.bun/bin/pi` |
| pi-lmstudio | 1.5.0 | `~/.pi/agent/npm/node_modules/pi-lmstudio` |
| TelePi | 0.4.2 | `~/.bun/bin/telepi` |
| Bun | 1.3.14 | `~/.bun/bin/bun` |
