# Local Agent Setup: Pi + LM Studio + Qwen 3.8 27B + TelePi

Guide for running a **local coding agent** on this machine with **Qwen 3.8 27B** in LM Studio, **Pi** as the agent harness, and **TelePi** for Telegram access from your phone.

Tested on **Windows 11 + WSL2 (Ubuntu)**. LM Studio runs on Windows; Pi and TelePi run in WSL.

---

## Architecture

```text
Phone (Telegram)
    ↕ TelePi (WSL, always-on service)
    ↕ Pi coding agent (WSL)
    ↕ LM Studio API (Windows, port 1234)
    ↕ Qwen 3.8 27B (local GPU/RAM)
```

---

## Why WSL (not native Windows)

The `curl -fsSL https://pi.dev/install.sh | bash` installer often **fails on Windows** because the environment mixes:

- **Linux Node** (from Cursor/WSL tooling)
- **Windows npm** (`/mnt/c/Program Files/nodejs/npm`)

That causes `npm error Maximum call stack size exceeded` when Pi tries to install extensions.

**Fix:** Install and run Pi entirely in **WSL** using **Bun** as the package manager.

---

## Prerequisites

- Windows 11 with WSL2 (Ubuntu)
- LM Studio installed on **Windows**
- Qwen 3.8 27B loaded in LM Studio
- Telegram account (for TelePi)

---

## One-time install (WSL)

### 1. Ensure Bun is on PATH

Bun should already be in `~/.bashrc`:

```bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
source ~/.bashrc
```

If Bun is missing:

```bash
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc
```

### 2. Install Pi and TelePi

```bash
bun install -g @earendil-works/pi-coding-agent
bun install -g @futurelab-studio/telepi
```

Verify:

```bash
pi --version      # e.g. 0.84.2
telepi version    # e.g. 0.4.2
```

### 3. Install pi-lmstudio extension

Pi's `pi install` uses npm by default (broken on this machine). Use Bun instead.

**Option A — automated script in this repo:**

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/setup-pi-telepi-wsl.sh
```

**Option B — manual:**

```bash
mkdir -p ~/.pi/agent/npm
cd ~/.pi/agent/npm
bun init -y
bun add pi-lmstudio
```

Register the extension in `~/.pi/agent/settings.json`:

```json
{
  "npmCommand": ["bun"],
  "packages": ["npm:pi-lmstudio"],
  "shellPath": "/bin/bash"
}
```

Verify:

```bash
pi list
# should show: npm:pi-lmstudio
```

---

## LM Studio (Windows)

### Load the model

1. Open **LM Studio** on Windows.
2. Load **qwen/qwen3.8-27b**.
3. Use a quant that fits your VRAM/RAM (e.g. Q4_K_M ~17GB).

### Server settings

1. **Developer tab → Start Server** (port **1234** by default).
2. Set **context length to 32k minimum** (not 8192 — Qwen thinking will consume it all).
3. Set **reasoning effort to medium or low** (default `xhigh` is extremely slow and token-heavy).

### Critical: expose server to WSL

By default LM Studio binds to **`127.0.0.1` only**. WSL **cannot** reach Windows localhost in NAT mode.

**Symptom:** LM Studio appears running, but from WSL:

```bash
curl http://172.28.112.1:1234/v1/models   # times out
```

**Fix — bind to all interfaces:**

Edit `C:\Users\cjfit\.lmstudio\.internal\http-server-config.json`:

```json
{
  "networkInterface": "0.0.0.0",
  "port": 1234
}
```

Then restart the server from PowerShell or WSL:

```powershell
lms server stop
lms server start --bind 0.0.0.0
```

Or from WSL:

```bash
/mnt/c/Users/cjfit/.lmstudio/bin/lms.exe server stop
/mnt/c/Users/cjfit/.lmstudio/bin/lms.exe server start --bind 0.0.0.0
```

**Verify from WSL:**

```bash
HOST=$(ip route show default | awk '{print $3}')
echo "Windows host IP: $HOST"
curl "http://${HOST}:1234/v1/models"
```

You should see `qwen/qwen3.8-27b` in the response.

### Alternative: WSL mirrored networking

If you prefer LM Studio to stay on `127.0.0.1`, create `C:\Users\cjfit\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Then run `wsl --shutdown` and reopen WSL. Pi can then use `http://127.0.0.1:1234/v1`.

---

## Pi configuration (WSL)

Config directory: `~/.pi/agent/`

### Detect Windows host IP

The WSL gateway IP can change after reboot. Use:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/detect-lmstudio-host.sh
```

Typical value: `172.28.112.1` (your default gateway from `ip route`).

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

Replace `172.28.112.1` with your current gateway IP if different.

Use `"api": "openai-responses"` only if chat completions misbehave; `openai-completions` worked in testing.

Model `id` must match LM Studio exactly — check with:

```bash
curl "http://${HOST}:1234/v1/models"
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

### `~/.pi/agent/auth.json`

```json
{
  "lmstudio": {
    "type": "api_key",
    "key": "lm-studio"
  }
}
```

LM Studio ignores the key locally; Pi requires a non-empty value.

### `~/.pi/agent/settings.json`

```json
{
  "npmCommand": ["bun"],
  "packages": ["npm:pi-lmstudio"],
  "shellPath": "/bin/bash"
}
```

---

## Smoke test Pi + Qwen

```bash
source ~/.bashrc
cd ~/repos/random-general-repo-cursor-remote-control

pi --list-models
# expect: lmstudio  qwen/qwen3.8-27b

# quick non-interactive test (~30s first run)
pi -p --provider lmstudio --model qwen/qwen3.8-27b --thinking low --no-tools "Reply with exactly: pi-ok"
# expect: pi-ok

# or use repo script
~/repos/random-general-repo-cursor-remote-control/scripts/pi-smoke-test.sh
```

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

TelePi bridges Telegram ↔ Pi sessions on your PC.

### 1. Create a Telegram bot

1. Message [@BotFather](https://t.me/BotFather) → `/newbot`
2. Save the **bot token**

### 2. Get your Telegram user ID

1. Message [@userinfobot](https://t.me/userinfobot)
2. Save your **numeric user ID**

### 3. Run setup (WSL)

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
TELEGRAM_ALLOWED_USER_IDS=...
DEFAULT_WORKSPACE=/home/chris/repos/random-general-repo-cursor-remote-control
```

Example template: `~/.config/telepi/config.env.example`

### 4. Enable user service persistence

```bash
loginctl enable-linger "$USER"
systemctl --user status telepi.service
telepi status
```

### 5. Daily use

1. Start Pi in your repo: `pi`
2. In Pi, run: `/handoff`
3. Open Telegram → your bot → `/start`
4. Send prompts from your phone
5. Use `/handback` in Telegram to resume in the terminal

---

## After reboot checklist

1. **Start LM Studio** on Windows and load Qwen 3.8 27B.
2. **Start server** with network bind:
   ```bash
   /mnt/c/Users/cjfit/.lmstudio/bin/lms.exe server start --bind 0.0.0.0
   ```
3. **Verify WSL can reach it:**
   ```bash
   curl "http://$(ip route show default | awk '{print $3}'):1234/v1/models"
   ```
4. **Update Pi baseUrl** if gateway IP changed (run `detect-lmstudio-host.sh`).
5. **Check TelePi service:**
   ```bash
   telepi status
   systemctl --user restart telepi.service   # if needed
   ```

---

## Repo helper scripts

| Script | Purpose |
|--------|---------|
| `scripts/setup-pi-telepi-wsl.sh` | One-shot install + config |
| `scripts/detect-lmstudio-host.sh` | Find reachable LM Studio host IP |
| `scripts/pi-smoke-test.sh` | Test LM Studio + Pi end-to-end |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `curl` to `:1234` times out from WSL | LM Studio bound to `127.0.0.1` only | Bind `0.0.0.0` (see above) |
| Pi `Request timed out` | LM Studio down, or xhigh reasoning | Start server; use `--thinking low` |
| `pi install` stack overflow | Windows npm | Use `"npmCommand": ["bun"]` in settings |
| Empty tool calls / no execution | Wrong API mode or context too small | Try `openai-completions`; set 32k+ context |
| Gateway IP changed | WSL restart | Re-run `detect-lmstudio-host.sh`, update `models.json` |
| TelePi bot silent | Service not running / wrong token | `telepi status`, check `config.env` |

---

## Security notes

- Binding LM Studio to `0.0.0.0` exposes the API on your **local network**. Fine at home; enable LM Studio authentication on shared networks.
- TelePi uses a **user ID allowlist** — only your Telegram ID can control the bot.
- A local agent with shell/file tools is effectively **remote code execution** on your PC. Keep TelePi locked to your user ID only.

---

## Why these tools (decision log)

| Option | Verdict |
|--------|---------|
| **Cursor Cloud Agent** | Already used for remote control; different use case |
| **OpenClaw** | Best for multi-channel messaging; heavier |
| **OpenCode** | Good TUI; more LM Studio + Qwen friction reported |
| **Oh My Pi** | Pi++ ; unproven with Qwen 3.8 27B locally |
| **Pi + TelePi** | **Chosen** — proven Qwen 3.8 agent loop, Telegram via extension |

---

## Quick reference commands

```bash
# PATH (each new shell)
source ~/.bashrc

# Pi
pi --list-models
pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium

# LM Studio from WSL
/mnt/c/Users/cjfit/.lmstudio/bin/lms.exe server status
/mnt/c/Users/cjfit/.lmstudio/bin/lms.exe server start --bind 0.0.0.0

# TelePi
telepi status
telepi setup
systemctl --user status telepi.service
```

---

## Verified working (2026-08-18)

- LM Studio reachable from WSL at `http://172.28.112.1:1234/v1/models` after `networkInterface: 0.0.0.0`
- `pi -p ... "Reply with exactly: pi-ok"` → **`pi-ok`** (~29s, `--thinking low --no-tools`)
- Pi 0.84.2, pi-lmstudio 1.5.0, TelePi 0.4.2 installed in WSL
- **Not yet completed:** `telepi setup` with real bot token (you must provide credentials)

---

*Last updated: 2026-08-18. Environment: WSL2 Ubuntu on MINIPC-3D9PL, LM Studio on Windows, user `chris`.*
