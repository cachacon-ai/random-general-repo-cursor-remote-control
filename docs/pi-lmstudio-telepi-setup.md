# Pi + LM Studio + TelePi setup (WSL on Windows)

Guide for running a **local coding agent** with **Qwen 3.8 27B** in LM Studio, **Pi** as the harness, and **TelePi** for Telegram access from your phone.

This repo also includes helper scripts under `scripts/`.

---

## Architecture

```text
Phone (Telegram)
    ↕ TelePi (WSL, systemd user service)
Pi coding agent (WSL)
    ↕ HTTP OpenAI-compatible API
LM Studio (Windows) → Qwen 3.8 27B
```

- **LM Studio** runs on **Windows** (GPU).
- **Pi + TelePi** run in **WSL** (Ubuntu).
- Do **not** use Windows `npm` from WSL — it breaks Pi installs. Use **Bun** in WSL instead.

---

## Why the default Windows install failed

| Problem | Cause | Fix |
|---------|-------|-----|
| `curl -fsSL https://pi.dev/install.sh \| bash` fails | Install script often returns 500; also wrong path on Windows | Install in **WSL** with Bun |
| `pi install npm:pi-lmstudio` fails with stack overflow | WSL uses **Linux Node** but **Windows npm** (`/mnt/c/Program Files/nodejs/npm`) | Set `"npmCommand": ["bun"]` in `~/.pi/agent/settings.json` |
| WSL cannot reach LM Studio | Server bound to `127.0.0.1` only on Windows | Bind to `0.0.0.0` (see below) |

---

## Installed components (WSL)

| Tool | Path | Install command |
|------|------|-----------------|
| Bun | `~/.bun/bin/bun` | `curl -fsSL https://bun.sh/install \| bash` |
| Pi | `~/.bun/bin/pi` | `bun install -g @earendil-works/pi-coding-agent` |
| pi-lmstudio | `~/.pi/agent/npm/` | `cd ~/.pi/agent/npm && bun add pi-lmstudio` |
| TelePi | `~/.bun/bin/telepi` | `bun install -g @futurelab-studio/telepi` |

Ensure `~/.bashrc` includes:

```bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
```

Then: `source ~/.bashrc`

Verify:

```bash
pi --version      # e.g. 0.84.2
telepi version    # e.g. 0.4.2
```

---

## Config files (WSL)

| File | Purpose |
|------|---------|
| `~/.pi/agent/settings.json` | Pi settings; use `"npmCommand": ["bun"]`, register `npm:pi-lmstudio` |
| `~/.pi/agent/models.json` | LM Studio provider + Qwen model |
| `~/.pi/agent/lmstudio.json` | LM Studio URL(s) for pi-lmstudio extension |
| `~/.pi/agent/auth.json` | Dummy API key for local LM Studio |
| `~/.config/telepi/config.env` | TelePi bot token, allowed user IDs, workspace |

### Example `~/.pi/agent/settings.json`

```json
{
  "npmCommand": ["bun"],
  "packages": ["npm:pi-lmstudio"],
  "shellPath": "/bin/bash"
}
```

### Example `~/.pi/agent/models.json`

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

> **Note:** Simon Willison used `openai-responses` successfully with Pi. If tool calling misbehaves, try `openai-completions` (current default here) or switch to `openai-responses`.

### Example `~/.pi/agent/lmstudio.json`

```json
{
  "urls": [
    { "name": "windows", "url": "http://172.28.112.1:1234" },
    { "name": "local", "url": "http://127.0.0.1:1234" }
  ]
}
```

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

- Open **LM Studio** on Windows.
- Load **qwen/qwen3.8-27b** (or your preferred Qwen 3.8 quant).

### 2. Server settings

- **Developer tab → Start Server** (port `1234` by default).
- Set **context to 32k minimum** (not 8192 — Qwen thinking will consume it).
- Set **reasoning effort to medium or low** (not `xhigh` for everyday use).

### 3. Critical: WSL network binding

By default LM Studio binds to **`127.0.0.1` only**. WSL **cannot** reach Windows localhost in NAT mode.

**Symptom:** LM Studio appears running; `curl http://172.28.112.1:1234/v1/models` from WSL times out.

**Fix A — Bind to all interfaces (used in this setup):**

Edit `C:\Users\cjfit\.lmstudio\.internal\http-server-config.json`:

```json
"networkInterface": "0.0.0.0"
```

Restart the server:

```powershell
lms server stop
lms server start --bind 0.0.0.0
```

Or from WSL:

```bash
/mnt/c/Users/cjfit/.lmstudio/bin/lms.exe server stop
/mnt/c/Users/cjfit/.lmstudio/bin/lms.exe server start --bind 0.0.0.0
```

**Fix B — WSL mirrored networking (alternative):**

Create `C:\Users\cjfit\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Then run `wsl --shutdown` and reopen WSL. Pi can then use `http://127.0.0.1:1234/v1` and LM Studio can stay on localhost.

### 4. Verify from WSL

```bash
# Detect gateway IP
ip route show default | awk '{print $3}'

# Should return JSON model list including qwen/qwen3.8-27b
curl "http://$(ip route show default | awk '{print $3}'):1234/v1/models"
```

Or use the repo script:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/detect-lmstudio-host.sh
```

### Security note

Binding to `0.0.0.0` exposes the API on your LAN. Fine for home use; enable LM Studio authentication on shared networks.

---

## Pi usage

### List models

```bash
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

Or run:

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

- Telegram bot token from [@BotFather](https://t.me/BotFather) (`/newbot`)
- Your numeric Telegram user ID from [@userinfobot](https://t.me/userinfobot)
- Pi working locally first

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
telepi status
```

### Daily workflow

1. Start LM Studio server on Windows (with `0.0.0.0` bind if using NAT WSL).
2. In WSL: `cd ~/repos/random-general-repo-cursor-remote-control && pi`
3. In Pi: `/handoff`
4. On phone: open your Telegram bot → `/start` → send prompts
5. When back at desk: `/handback` in Telegram to resume in terminal

---

## Repo helper scripts

Run the full setup (reinstall/config refresh):

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/setup-pi-telepi-wsl.sh
```

| Script | Purpose |
|--------|---------|
| `scripts/setup-pi-telepi-wsl.sh` | Install Pi/TelePi via Bun, write config templates |
| `scripts/detect-lmstudio-host.sh` | Find reachable LM Studio host IP from WSL |
| `scripts/pi-smoke-test.sh` | curl + `pi --list-models` + quick prompt test |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| WSL curl to `:1234` times out | LM Studio on `127.0.0.1` only | Bind `0.0.0.0` (see above) |
| `pi install` npm stack overflow | Windows npm in WSL | Use Bun; `"npmCommand": ["bun"]` |
| Pi `Request timed out` | Model thinking too long / server down | Lower thinking; confirm curl works |
| Empty tool calls / no file reads | Wrong API mode or reasoning too high | Try `openai-completions`, `--thinking low` |
| Gateway IP changed after reboot | WSL NAT IP drift | Re-run `detect-lmstudio-host.sh`, update `models.json` |
| TelePi bot silent | Service not running / wrong token | `telepi status`, check `config.env` |

---

## After reboot checklist

1. **Windows:** Start LM Studio, load Qwen 3.8 27B.
2. **Windows:** `lms server start --bind 0.0.0.0` (if not using mirrored WSL).
3. **WSL:** `curl http://$(ip route show default | awk '{print $3}'):1234/v1/models`
4. **WSL:** `pi --list-models`
5. **WSL:** `telepi status` (TelePi should auto-start if systemd user service enabled)

---

## Decision log (why Pi, not Goose/OpenClaw/Oh My Pi)

- **Pi + Qwen 3.8 27B** is documented working (Simon Willison, LM Studio, tool calling).
- **TelePi** adds Telegram without building a bot yourself.
- **Goose** has built-in Telegram but more LM Studio+Qwen friction; good fallback.
- **Oh My Pi** is Pi++ (32 tools, heavier context); try only after Pi works and feels too minimal.

---

## References

- [Pi coding agent](https://github.com/badlogic/pi-mono)
- [pi-lmstudio extension](https://www.npmjs.com/package/pi-lmstudio)
- [TelePi](https://github.com/williamleong/TelePi)
- [LM Studio — Serve on Local Network](https://lmstudio.ai/docs/developer/core/server/serve-on-network)
- [Qwen 3.8 27B — Simon Willison](https://simonwillison.net/2026/Aug/16/qwen-38-27b/)
