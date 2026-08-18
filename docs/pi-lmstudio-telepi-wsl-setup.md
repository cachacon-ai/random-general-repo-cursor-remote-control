# Pi + LM Studio + Qwen 3.8 27B + TelePi (WSL on Windows)

Guide for running a **local coding agent** on WSL, using **Qwen 3.8 27B** in **LM Studio** on Windows, with **Telegram** access via **TelePi**.

Last updated: 2026-08-18

---

## Architecture

```text
Phone (Telegram)
    ↕ TelePi (WSL, always-on service)
Pi coding agent (WSL)
    ↕ HTTP OpenAI-compatible API
LM Studio (Windows, GPU)
    ↕
Qwen 3.8 27B (local)
```

- **LM Studio** runs on **Windows** (GPU access).
- **Pi + TelePi** run in **WSL**.
- WSL reaches LM Studio via the Windows host IP (default gateway), **not** `127.0.0.1` inside WSL (unless WSL mirrored networking is enabled).

---

## Why not native Windows / `curl | bash`?

The install script at `https://pi.dev/install.sh` may fail on Windows. A common WSL issue is a mixed toolchain:

- Linux Node from Cursor/agent
- Windows npm at `/mnt/c/Program Files/nodejs/npm`

That breaks `pi install` with `Maximum call stack size exceeded`.

**Fix:** Install Pi with **Bun** inside WSL, and set `"npmCommand": ["bun"]` in Pi settings.

---

## Prerequisites

- Windows 11 with WSL2 (Ubuntu)
- LM Studio installed on Windows
- Qwen 3.8 27B downloaded in LM Studio
- Telegram account (for TelePi)

---

## One-time install (WSL)

### 1. Install Bun (if missing)

```bash
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc
export PATH="$HOME/.bun/bin:$PATH"
```

`~/.bashrc` should already contain:

```bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
```

### 2. Install Pi coding agent

```bash
bun install -g @earendil-works/pi-coding-agent
pi --version   # expect 0.84.x
```

Do **not** use Windows npm for Pi in WSL.

### 3. Install pi-lmstudio extension

Pi's `pi install npm:pi-lmstudio` may fail if it invokes Windows npm. Install manually with Bun:

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

Verify:

```bash
pi list
# should show: npm:pi-lmstudio
```

### 4. Install TelePi

```bash
bun install -g @futurelab-studio/telepi
telepi version   # expect 0.4.x
```

### 5. Repo setup scripts (optional)

From this repo:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/setup-pi-telepi-wsl.sh
```

Scripts included:

| Script | Purpose |
|--------|---------|
| `scripts/setup-pi-telepi-wsl.sh` | Install/refresh Pi, pi-lmstudio, TelePi configs |
| `scripts/detect-lmstudio-host.sh` | Find reachable LM Studio host IP from WSL |
| `scripts/pi-smoke-test.sh` | Curl + `pi --list-models` + one-shot prompt test |

---

## LM Studio (Windows)

### Load the model

1. Open LM Studio on **Windows**.
2. Load **qwen/qwen3.8-27b**.
3. Use a quant that fits your VRAM (Q4_K_M ~17GB is common).

### Model settings (important)

| Setting | Recommendation |
|---------|----------------|
| Context length | **32k minimum** (not default 8k) |
| Reasoning effort | **medium** or **low** (not default xhigh) |
| Preserve thinking | Optional; helps agents but uses more context |

Qwen 3.8 defaults to aggressive reasoning (`xhigh`), which can burn tens of thousands of tokens before replying.

### Start the server

**Developer tab → Start Server** (port 1234 by default).

### Critical: WSL cannot reach localhost-only binding

By default LM Studio binds to **`127.0.0.1`**. WSL **cannot** connect to that.

Verify from Windows PowerShell:

```powershell
Get-NetTCPConnection -LocalPort 1234 | Select LocalAddress, State
# If LocalAddress is 127.0.0.1 only → WSL will fail
```

#### Fix A — Bind to all interfaces (recommended for NAT WSL)

Edit `C:\Users\<you>\.lmstudio\.internal\http-server-config.json`:

```json
{
  "networkInterface": "0.0.0.0",
  "port": 1234
}
```

Restart server via CLI:

```powershell
lms server stop
lms server start --bind 0.0.0.0
```

**Security:** `0.0.0.0` exposes the API on your LAN. Enable LM Studio authentication on shared networks.

#### Fix B — WSL mirrored networking (keep LM Studio on localhost)

Create `C:\Users\<you>\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Then:

```powershell
wsl --shutdown
```

Reopen WSL. Pi can then use `http://127.0.0.1:1234/v1`.

### Test from WSL

```bash
# Windows host IP (usually WSL default gateway)
HOST=$(ip route show default | awk '{print $3}')
echo $HOST   # e.g. 172.28.112.1

curl "http://${HOST}:1234/v1/models"
# should list qwen/qwen3.8-27b
```

Or:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/detect-lmstudio-host.sh
```

---

## Pi configuration (WSL)

### `~/.pi/agent/models.json`

Replace `HOST` with your WSL gateway IP (from `ip route show default`):

```json
{
  "providers": {
    "lmstudio": {
      "baseUrl": "http://HOST:1234/v1",
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

Notes:

- Use the exact model `id` from `curl http://HOST:1234/v1/models`.
- `openai-completions` worked reliably in testing. `openai-responses` is an alternative if your LM Studio build supports it well.
- If the gateway IP changes after reboot, re-run `detect-lmstudio-host.sh` and update `baseUrl`.

### `~/.pi/agent/lmstudio.json`

```json
{
  "urls": [
    { "name": "windows", "url": "http://HOST:1234" },
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

LM Studio ignores the key value; Pi requires a non-empty key.

### `~/.pi/agent/settings.json`

```json
{
  "npmCommand": ["bun"],
  "packages": ["npm:pi-lmstudio"],
  "shellPath": "/bin/bash"
}
```

---

## Verify Pi + Qwen

```bash
export PATH="$HOME/.bun/bin:$PATH"
cd ~/repos/random-general-repo-cursor-remote-control

pi --list-models
# expect: lmstudio  qwen/qwen3.8-27b

# one-shot test (first run may take 30–90s)
pi -p --provider lmstudio --model qwen/qwen3.8-27b --thinking low --no-tools "Reply exactly: pi-ok"
# expect: pi-ok

# interactive session
pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium
```

Inside Pi: `/model` to switch models.

Full smoke test script:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/pi-smoke-test.sh
```

### Tool-calling test

```bash
pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium
# prompt: "List files in this directory and summarize README.md"
```

Confirm it actually runs tools (reads files), not just describes what it would do.

---

## TelePi (Telegram)

### A. Create Telegram bot

1. Message [@BotFather](https://t.me/BotFather) → `/newbot`
2. Save the **bot token**

### B. Get your Telegram user ID

1. Message [@userinfobot](https://t.me/userinfobot)
2. Save your **numeric user ID**

### C. Run setup (WSL)

Interactive:

```bash
telepi setup
```

Non-interactive:

```bash
telepi setup "YOUR_BOT_TOKEN" "YOUR_TELEGRAM_ID" "/home/chris/repos/random-general-repo-cursor-remote-control"
```

Config file: `~/.config/telepi/config.env`

```bash
TELEGRAM_BOT_TOKEN=...
TELEGRAM_ALLOWED_USER_IDS=123456789
DEFAULT_WORKSPACE=/home/chris/repos/random-general-repo-cursor-remote-control
```

Template: `~/.config/telepi/config.env.example`

### D. Keep TelePi running after logout

```bash
loginctl enable-linger "$USER"
systemctl --user status telepi.service
systemctl --user restart telepi.service
```

### E. Daily use

1. Start Pi in your repo (WSL):
   ```bash
   cd ~/repos/random-general-repo-cursor-remote-control
   pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium
   ```
2. In Pi, run `/handoff`
3. Open Telegram → your bot → `/start`
4. Send prompts from phone (text, voice, images supported)
5. `/handback` in Telegram to resume in terminal

Check status:

```bash
telepi status
```

---

## After reboot checklist

1. **Windows:** Start LM Studio, load Qwen 3.8 27B, start server.
2. **If using bind fix:** confirm server is on `0.0.0.0`:
   ```powershell
   lms server start --bind 0.0.0.0
   ```
3. **WSL:** Verify connectivity:
   ```bash
   curl "http://$(ip route show default | awk '{print $3}'):1234/v1/models"
   ```
4. **WSL:** Confirm TelePi service:
   ```bash
   telepi status
   ```

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| WSL curl to `:1234` times out | LM Studio on `127.0.0.1` only | Bind `0.0.0.0` or enable WSL mirrored networking |
| `pi install` stack overflow | Windows npm in WSL | Use `"npmCommand": ["bun"]`, install extensions with `bun add` |
| Pi `Request timed out` | LM Studio down, xhigh reasoning, or 8k context | Start server, set medium/low reasoning, increase context |
| `pi --list-models` works but prompts fail | Stale cache / server stopped | Restart LM Studio server, re-test curl |
| Gateway IP changed | WSL restart | Re-run `detect-lmstudio-host.sh`, update `models.json` |
| TelePi no response | Service not running / bad token | `telepi status`, `systemctl --user restart telepi.service` |
| Slow responses | 27B local inference | Normal (15–30+ tok/s); use `--thinking low` for quick tasks |

---

## Harness options (why Pi?)

This setup uses **Pi** because Qwen 3.8 27B + LM Studio + tool calling was **verified** on Pi (not Oh My Pi or Goose).

| Harness | Telegram | Qwen 3.8 local | Notes |
|---------|----------|----------------|-------|
| **Pi + TelePi** | Via TelePi extension | Proven | This guide |
| **Goose** | Built-in gateway | Less proven locally | Easier phone setup |
| **Oh My Pi** | Via omp-telegram | Unproven on 3.8 27B | Heavier harness |
| **OpenCode** | DIY | LM Studio friction reported | Strong TUI/LSP |

---

## File locations reference

| Path | Purpose |
|------|---------|
| `~/.bun/bin/pi` | Pi CLI |
| `~/.bun/bin/telepi` | TelePi CLI |
| `~/.pi/agent/settings.json` | Pi settings + packages |
| `~/.pi/agent/models.json` | LM Studio provider + Qwen model |
| `~/.pi/agent/lmstudio.json` | pi-lmstudio extension URLs |
| `~/.pi/agent/auth.json` | LM Studio dummy API key |
| `~/.config/telepi/config.env` | TelePi bot token + allowlist |
| `C:\Users\<you>\.lmstudio\.internal\http-server-config.json` | LM Studio bind address |
| `~/repos/random-general-repo-cursor-remote-control/scripts/` | Setup helper scripts |

---

## Quick command reference

```bash
# PATH (each new shell, or in ~/.bashrc)
export PATH="$HOME/.bun/bin:$PATH"

# LM Studio host
export LMS_HOST="$(ip route show default | awk '{print $3}')"

# Test LM Studio
curl "http://${LMS_HOST}:1234/v1/models"

# Pi
pi --list-models
pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium

# TelePi
telepi setup
telepi status
```
