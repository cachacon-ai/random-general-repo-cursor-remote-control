# Pi + LM Studio + Qwen 3.8 27B + TelePi (WSL Setup Guide)

This guide documents how to run a **local coding agent** on WSL using:

- **LM Studio** on Windows (serves Qwen models)
- **Pi** in WSL (agent harness)
- **TelePi** in WSL (Telegram bridge for phone access)

It reflects the setup performed on this machine and the fixes needed for WSL ↔ Windows networking.

---

## Recommended stack

```text
Phone (Telegram)
      ↓
   TelePi (WSL)
      ↓
     Pi (WSL)
      ↓
 LM Studio (Windows) → Qwen 3.8 27B
```

**Why this stack:** Pi is proven with Qwen 3.8 27B locally. TelePi adds Telegram without building a custom bot. LM Studio stays on Windows where the GPU lives.

---

## Why not native Windows Pi?

The `curl -fsSL https://pi.dev/install.sh | bash` path often fails on Windows/WSL hybrid setups because:

- **Linux Node** may be used alongside **Windows npm** (`/mnt/c/Program Files/nodejs/npm`)
- That mix caused `Maximum call stack size exceeded` during `pi install`

**Fix:** Install Pi in **WSL using Bun**, not Windows npm.

---

## Prerequisites

- Windows with **LM Studio** installed
- **WSL2** (Ubuntu)
- Model loaded: **qwen/qwen3.8-27b** (or your preferred Qwen variant)
- Telegram bot token (for TelePi, later)

---

## Part 1 — Install tools in WSL

Open a **WSL terminal** and run:

```bash
# Bun (if missing)
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc
export PATH="$HOME/.bun/bin:$PATH"

# Pi coding agent
bun install -g @earendil-works/pi-coding-agent

# TelePi (Telegram bridge)
bun install -g @futurelab-studio/telepi

# Verify
pi --version      # expect 0.84.x
telepi version    # expect 0.4.x
```

Ensure `~/.bashrc` includes:

```bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
```

Or run the repo setup script:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/setup-pi-telepi-wsl.sh
```

---

## Part 2 — Install pi-lmstudio extension

Pi's `pi install npm:pi-lmstudio` uses npm by default. Configure Bun instead.

### `~/.pi/agent/settings.json`

```json
{
  "npmCommand": ["bun"],
  "packages": ["npm:pi-lmstudio"],
  "shellPath": "/bin/bash"
}
```

If `pi install` fails, install manually:

```bash
mkdir -p ~/.pi/agent/npm
cd ~/.pi/agent/npm
bun init -y
bun add pi-lmstudio
```

Verify:

```bash
pi list
# should show: npm:pi-lmstudio
```

---

## Part 3 — LM Studio on Windows

1. Open **LM Studio** on Windows (not WSL).
2. Load **qwen/qwen3.8-27b**.
3. **Developer tab → Start Server** (port 1234 by default).
4. Set **context to 32k+** (not 8192 — Qwen thinking will consume it).
5. Set **reasoning effort to medium or low** (not `xhigh` for everyday use).

### Critical: WSL cannot reach Windows localhost

By default, LM Studio binds to **`127.0.0.1` only**. WSL is a separate network namespace and **cannot** connect to Windows `127.0.0.1`.

**Symptoms:**

- LM Studio appears running in the GUI
- `curl http://172.28.x.x:1234/v1/models` from WSL times out
- Pi requests time out

**Verify from Windows PowerShell:**

```powershell
Invoke-WebRequest http://127.0.0.1:1234/v1/models
Get-NetTCPConnection -LocalPort 1234
# If LocalAddress is 127.0.0.1 only → WSL cannot connect
```

### Fix A — Bind LM Studio to all interfaces (recommended here)

Edit:

`C:\Users\cjfit\.lmstudio\.internal\http-server-config.json`

Change:

```json
"networkInterface": "127.0.0.1"
```

To:

```json
"networkInterface": "0.0.0.0"
```

Restart the server:

```powershell
lms server stop
lms server start --bind 0.0.0.0
```

**Security note:** `0.0.0.0` exposes the API on your LAN. Fine for home use; enable LM Studio authentication on shared networks.

### Fix B — WSL mirrored networking (alternative)

Create `C:\Users\cjfit\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Then from PowerShell:

```powershell
wsl --shutdown
```

Reopen WSL. With mirrored mode, WSL can reach Windows services via `127.0.0.1` and LM Studio can stay on localhost.

### Find the WSL → Windows host IP (NAT mode)

```bash
ip route show default | awk '{print $3}'
# Often: 172.28.112.1 (can change after reboot)
```

Or use the repo helper:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/detect-lmstudio-host.sh
```

Test connectivity:

```bash
curl http://172.28.112.1:1234/v1/models
```

---

## Part 4 — Configure Pi for LM Studio + Qwen

### `~/.pi/agent/lmstudio.json`

```json
{
  "urls": [
    { "name": "windows", "url": "http://172.28.112.1:1234" },
    { "name": "local", "url": "http://127.0.0.1:1234" }
  ]
}
```

Replace `172.28.112.1` with your actual WSL gateway IP if different.

### `~/.pi/agent/models.json`

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

Use the exact model id from:

```bash
curl http://172.28.112.1:1234/v1/models
```

**API note:** `openai-completions` worked reliably here. `openai-responses` is an alternative if your LM Studio build supports it well.

### `~/.pi/agent/auth.json`

```json
{
  "lmstudio": {
    "type": "api_key",
    "key": "lm-studio"
  }
}
```

LM Studio ignores the key locally; Pi still requires a non-empty value.

---

## Part 5 — Smoke test Pi

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
pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium
```

Inside Pi:

- `/model` — switch models
- `/help` — commands

---

## Part 6 — TelePi (Telegram from phone)

### A. Create a Telegram bot

1. Message [@BotFather](https://t.me/BotFather) → `/newbot`
2. Copy the **bot token**

### B. Get your Telegram user ID

1. Message [@userinfobot](https://t.me/userinfobot)
2. Copy your **numeric ID**

### C. Run TelePi setup (WSL)

Interactive:

```bash
telepi setup
```

Non-interactive:

```bash
telepi setup "YOUR_BOT_TOKEN" "YOUR_TELEGRAM_ID" "/home/chris/repos/random-general-repo-cursor-remote-control"
```

Config is written to: `~/.config/telepi/config.env`

Example:

```env
TELEGRAM_BOT_TOKEN=123456789:AAF...
TELEGRAM_ALLOWED_USER_IDS=111111111
DEFAULT_WORKSPACE=/home/chris/repos/random-general-repo-cursor-remote-control
```

### D. Keep TelePi running after logout

```bash
loginctl enable-linger "$USER"
systemctl --user status telepi.service
telepi status
```

### E. Daily usage

1. Start Pi in your repo: `pi`
2. Run `/handoff` inside Pi
3. Open Telegram → your bot → `/start`
4. Send prompts from your phone
5. `/handback` in Telegram to resume in the terminal

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---------|--------------|-----|
| WSL curl to `:1234` times out | LM Studio on `127.0.0.1` only | Bind `0.0.0.0` or enable WSL mirrored networking |
| Pi "Request timed out" | Same, or model in xhigh reasoning | Fix bind; set reasoning low/medium in LM Studio |
| `pi install` stack overflow | Windows npm in WSL | Use `"npmCommand": ["bun"]` in settings.json |
| Empty tool calls / no execution | Wrong API mode or context too small | Use `openai-completions`; context 32k+ |
| Gateway IP changed after reboot | WSL NAT | Re-run `detect-lmstudio-host.sh`; update models.json |
| First response very slow | 27B local model cold start | Normal; subsequent turns faster |

---

## Repo helper scripts

| Script | Purpose |
|--------|---------|
| `scripts/setup-pi-telepi-wsl.sh` | Install Pi/TelePi, write config templates |
| `scripts/detect-lmstudio-host.sh` | Find reachable LM Studio host IP from WSL |
| `scripts/pi-smoke-test.sh` | Test LM Studio + Pi end-to-end |

---

## Config file locations (quick reference)

| File | Purpose |
|------|---------|
| `~/.pi/agent/settings.json` | Pi settings, npmCommand, packages |
| `~/.pi/agent/models.json` | LM Studio provider + Qwen model |
| `~/.pi/agent/lmstudio.json` | pi-lmstudio extension URLs |
| `~/.pi/agent/auth.json` | Local LM Studio API key placeholder |
| `~/.config/telepi/config.env` | TelePi bot token, user IDs, workspace |
| `C:\Users\cjfit\.lmstudio\.internal\http-server-config.json` | LM Studio bind address + port |

---

## After reboot checklist

1. Start LM Studio on Windows; load Qwen 3.8 27B
2. Ensure server is bound correctly:
   ```powershell
   lms server start --bind 0.0.0.0
   ```
3. From WSL: `curl http://$(ip route show default | awk '{print $3}'):1234/v1/models`
4. Run `pi-smoke-test.sh` or start `pi` interactively
5. Confirm TelePi: `telepi status` (restart if needed: `systemctl --user restart telepi.service`)

---

## What was validated on this machine

- Pi **0.84.2** installed via Bun in WSL
- pi-lmstudio **1.5.0** registered
- TelePi **0.4.2** installed
- LM Studio reachable from WSL after `networkInterface: 0.0.0.0`
- Pi smoke test returned **`pi-ok`** using `qwen/qwen3.8-27b` with `--thinking low`

TelePi final setup (bot token + `/handoff` flow) was prepared but requires your Telegram credentials via `telepi setup`.
