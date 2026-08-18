# Pi + LM Studio + TelePi on WSL (Windows)

Guide for running a **local coding agent** with **Qwen 3.8 27B** in LM Studio, **Pi** as the agent harness, and **TelePi** for Telegram access from your phone.

This setup runs in **WSL2** while LM Studio runs on **Windows**.

---

## Recommended stack

```text
LM Studio (Windows) — Qwen 3.8 27B
        ↓
       Pi (WSL) — agent harness
        ↓
     TelePi (WSL) — Telegram bridge
```

**Why not Goose / Oh My Pi / OpenCode?**

- **Pi** has the best documented results with Qwen 3.8 27B + LM Studio (minimal harness, smaller system prompt).
- **TelePi** adds Telegram without building your own bot.
- **Goose** is the fallback if Pi tool-calling is flaky (built-in Telegram, heavier harness).
- **Oh My Pi** is an upgrade path later if Pi works but feels too barebones.

---

## Why the Windows install script failed

The official installer fails in this environment:

```bash
curl -fsSL https://pi.dev/install.sh | bash   # often 500 / broken
pi install npm:pi-lmstudio                     # hits Windows npm
```

**Root cause:** WSL was using **Linux Node** but **Windows npm** (`/mnt/c/Program Files/nodejs/npm`), causing `Maximum call stack size exceeded`.

**Fix:** Install via **Bun in WSL**, and set `"npmCommand": ["bun"]` in Pi settings.

---

## Prerequisites

- Windows 11 + WSL2 (Ubuntu)
- LM Studio on Windows with **qwen/qwen3.8-27b** downloaded
- ~16GB+ RAM/VRAM for the 4-bit quant (more with large context)

---

## One-time install (WSL)

```bash
source ~/.bashrc
export PATH="$HOME/.bun/bin:$PATH"

# Bun (if missing)
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc

# Pi coding agent
bun install -g @earendil-works/pi-coding-agent

# pi-lmstudio extension (if pi install fails, use bun manually)
mkdir -p ~/.pi/agent/npm
cd ~/.pi/agent/npm && bun init -y && bun add pi-lmstudio

# TelePi
bun install -g @futurelab-studio/telepi
```

Or run the repo setup script:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/setup-pi-telepi-wsl.sh
```

Verify:

```bash
pi --version      # e.g. 0.84.2
telepi version    # e.g. 0.4.2
pi list           # should show npm:pi-lmstudio
```

---

## Pi configuration files

All under `~/.pi/agent/`:

### `settings.json`

```json
{
  "npmCommand": ["bun"],
  "packages": ["npm:pi-lmstudio"],
  "shellPath": "/bin/bash"
}
```

Using `"npmCommand": ["bun"]` avoids broken Windows npm when running `pi install`.

### `models.json`

Replace `172.28.112.1` with your WSL gateway IP (see below):

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

**Note:** Simon Willison used `"api": "openai-responses"` successfully on some setups. If tool calling misbehaves, try switching between `openai-completions` and `openai-responses`.

### `lmstudio.json`

```json
{
  "urls": [
    { "name": "windows", "url": "http://172.28.112.1:1234" },
    { "name": "local", "url": "http://127.0.0.1:1234" }
  ]
}
```

### `auth.json`

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

### Load the model

1. Open LM Studio on **Windows** (not WSL).
2. Load **qwen/qwen3.8-27b**.
3. Use a quant that fits your hardware (Q4_K_M ~17GB is common).

### Server settings

1. **Developer tab → Start Server** (port 1234).
2. Set **context to 32k minimum** (not 8192 — Qwen thinking will consume it all).
3. Set **reasoning effort to medium or low** (default `xhigh` is extremely slow).
4. Consider disabling **preserve thinking** for long agent sessions to save context.

### Critical: WSL cannot reach `127.0.0.1` on Windows

By default LM Studio binds to **localhost only** (`127.0.0.1`). WSL is a separate network namespace and **cannot** connect until the server listens on all interfaces.

**Symptom:** LM Studio appears running, but from WSL:
```bash
curl http://172.28.112.1:1234/v1/models   # times out
```

**Fix A — Bind to all interfaces (what we used):**

Edit `C:\Users\cjfit\.lmstudio\.internal\http-server-config.json`:

```json
"networkInterface": "0.0.0.0"
```

Then restart the server:

```powershell
lms server stop
lms server start --bind 0.0.0.0
```

**Fix B — WSL mirrored networking (alternative):**

Create `C:\Users\cjfit\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Run `wsl --shutdown`, reopen WSL. Then Pi can use `http://127.0.0.1:1234/v1` and LM Studio can stay on localhost.

**Security:** `0.0.0.0` exposes the API on your LAN. Fine at home; enable LM Studio auth on shared networks.

### Find your WSL → Windows gateway IP

```bash
ip route show default | awk '{print $3}'
# often 172.28.112.1 (can change after reboot)
```

Or use the repo helper:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/detect-lmstudio-host.sh
```

### Verify connectivity from WSL

```bash
curl http://172.28.112.1:1234/v1/models
# should return JSON listing qwen/qwen3.8-27b
```

---

## Pi usage

### List models

```bash
export PATH="$HOME/.bun/bin:$PATH"
pi --list-models
```

Expected:

```text
provider  model             context  max-out  thinking  images
lmstudio  qwen/qwen3.8-27b  128K     16.4K    yes       yes
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

First response may take **30–90 seconds** on a 27B local model.

### Interactive session

```bash
cd ~/repos/random-general-repo-cursor-remote-control
pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium
```

Inside Pi:

- `/model` — switch models
- `/handoff` — hand session to TelePi (after TelePi setup)

---

## TelePi (Telegram)

### Prerequisites

1. **Bot token** from [@BotFather](https://t.me/BotFather) (`/newbot`)
2. **Your numeric Telegram user ID** from [@userinfobot](https://t.me/userinfobot)
3. Pi working locally first (smoke test passes)

### Install (if not already)

```bash
bun install -g @futurelab-studio/telepi
```

### Setup

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

Example template: `~/.config/telepi/config.env.example`

### Keep TelePi running after logout

```bash
loginctl enable-linger "$USER"
systemctl --user status telepi.service
systemctl --user restart telepi.service   # if needed
```

### Daily workflow

1. Start LM Studio server on Windows (with `0.0.0.0` bind if using NAT networking).
2. In WSL: `cd ~/repos/random-general-repo-cursor-remote-control && pi`
3. In Pi: `/handoff`
4. On phone: open Telegram bot → `/start` → send prompts
5. When back at desk: `/handback` in Telegram to resume in terminal

### Check status

```bash
telepi status
```

---

## Repo helper scripts

| Script | Purpose |
|--------|---------|
| `scripts/setup-pi-telepi-wsl.sh` | Install Pi/TelePi, write config templates |
| `scripts/detect-lmstudio-host.sh` | Find reachable LM Studio host IP from WSL |
| `scripts/pi-smoke-test.sh` | Test LM Studio + Pi end-to-end |

---

## Troubleshooting

| Problem | Likely cause | Fix |
|---------|--------------|-----|
| `curl` to `:1234` times out from WSL | LM Studio on `127.0.0.1` only | Bind `0.0.0.0` or enable WSL mirrored networking |
| Pi `Request timed out` | Model thinking too long / server down | Lower thinking to `low`, confirm curl works |
| `pi install` stack overflow | Windows npm in WSL | Use `"npmCommand": ["bun"]` in settings.json |
| Empty tool calls / raw XML | Wrong API mode or LM Studio quirk | Try `openai-completions` vs `openai-responses` |
| Gateway IP changed after reboot | WSL NAT | Re-run `detect-lmstudio-host.sh`, update `models.json` |
| TelePi bot silent | Service not running / wrong token | `telepi status`, check `config.env` |

---

## After reboot checklist

1. Start LM Studio on Windows, load Qwen 3.8 27B.
2. Start server: `lms server start --bind 0.0.0.0` (if not using mirrored WSL).
3. From WSL: `curl http://$(ip route show default | awk '{print $3}'):1234/v1/models`
4. Update `~/.pi/agent/models.json` if gateway IP changed.
5. `pi --list-models` then start working.
6. TelePi should auto-start if systemd user service is enabled (`telepi status`).

---

## What's installed on this machine (WSL)

| Tool | Path | Version (at setup time) |
|------|------|-------------------------|
| Bun | `~/.bun/bin/bun` | 1.3.14 |
| Pi | `~/.bun/bin/pi` | 0.84.2 |
| TelePi | `~/.bun/bin/telepi` | 0.4.2 |
| pi-lmstudio | `~/.pi/agent/npm/node_modules/pi-lmstudio` | 1.5.0 |

PATH: `~/.bashrc` already includes `$HOME/.bun/bin`.

---

## References

- [Pi docs](https://pi.dev/)
- [pi-lmstudio](https://www.npmjs.com/package/pi-lmstudio)
- [TelePi](https://github.com/williamleong/TelePi)
- [LM Studio — Serve on Local Network](https://lmstudio.ai/docs/developer/core/server/serve-on-network)
- Simon Willison on Qwen 3.8 27B + Pi: https://simonwillison.net/2026/Aug/16/qwen-38-27b/
