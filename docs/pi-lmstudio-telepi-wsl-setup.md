# Pi + LM Studio + Qwen 3.8 27B + TelePi (WSL Setup)

Guide for running a **local coding agent** on WSL, powered by **Qwen 3.8 27B** in **LM Studio** on Windows, with **Telegram** access via **TelePi**.

This documents the working setup on Chris's machine (WSL2 + Windows LM Studio).

---

## Architecture

```text
Phone (Telegram)
      ↓
  TelePi (WSL, always-on service)
      ↓
  Pi coding agent (WSL)
      ↓
  LM Studio (Windows, port 1234)
      ↓
  Qwen 3.8 27B (local GPU/RAM)
```

- **LM Studio** runs on **Windows** (GUI + model inference).
- **Pi + TelePi** run in **WSL** (Ubuntu).
- WSL reaches LM Studio via the Windows host gateway IP (typically `172.28.x.1`), **not** `127.0.0.1`.

---

## Why not native Windows Pi?

The `curl -fsSL https://pi.dev/install.sh | bash` installer failed because this environment mixes:

- **Linux Node** (`~/.local/share/cursor-agent/.../node`)
- **Windows npm** (`/mnt/c/Program Files/nodejs/npm`)

That causes `npm install` to fail with `Maximum call stack size exceeded`.

**Fix:** Install Pi in WSL using **Bun**, not Windows npm.

---

## Installed components (WSL)

| Tool | Path | Version (at setup) |
|------|------|-------------------|
| Bun | `~/.bun/bin/bun` | 1.3.14 |
| Pi | `~/.bun/bin/pi` | 0.84.2 |
| pi-lmstudio | `~/.pi/agent/npm/node_modules/pi-lmstudio` | 1.5.0 |
| TelePi | `~/.bun/bin/telepi` | 0.4.2 |

Bun/Pi are on PATH via `~/.bashrc`:

```bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
```

---

## One-time install (WSL)

```bash
# Install Bun (if missing)
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc

# Install Pi + TelePi
bun install -g @earendil-works/pi-coding-agent
bun install -g @futurelab-studio/telepi

# Install pi-lmstudio extension (use bun, not Windows npm)
mkdir -p ~/.pi/agent/npm
cd ~/.pi/agent/npm
bun init -y
bun add pi-lmstudio
```

Or run the repo setup script:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/setup-pi-telepi-wsl.sh
```

---

## Pi configuration files

All under `~/.pi/agent/`:

### `settings.json`

Uses Bun for `pi install` (avoids broken Windows npm):

```json
{
  "npmCommand": ["bun"],
  "packages": ["npm:pi-lmstudio"],
  "shellPath": "/bin/bash"
}
```

### `models.json`

Point at LM Studio on the Windows host. **Use the gateway IP**, not localhost:

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

Find your Windows host IP from WSL:

```bash
ip route show default | awk '{print $3}'
# or
~/repos/random-general-repo-cursor-remote-control/scripts/detect-lmstudio-host.sh
```

Update `baseUrl` if the gateway IP changes after reboot.

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

## LM Studio (Windows)

### Load the model

1. Open **LM Studio** on Windows.
2. Load **qwen/qwen3.8-27b**.
3. Use a quant that fits your VRAM/RAM (e.g. Q4_K_M ~17GB).

### Model settings (important)

| Setting | Recommendation |
|---------|----------------|
| Context length | **32k minimum** (not default 8k) |
| Reasoning effort | **medium** or **low** (not default xhigh) |
| Preserve thinking | Optional; useful for agents but eats context |

### Start the server

**Developer tab → Start Server** (port 1234).

---

## Critical fix: WSL cannot reach 127.0.0.1 on Windows

By default, LM Studio binds to **`127.0.0.1` only**. WSL will **timeout** even if the server appears running in the LM Studio GUI.

**Symptom:** `curl http://172.28.x.x:1234/v1/models` times out from WSL, but works in Windows PowerShell against `127.0.0.1`.

**Verify on Windows (PowerShell):**

```powershell
Get-NetTCPConnection -LocalPort 1234 | Select LocalAddress, State
# Bad for WSL:  LocalAddress = 127.0.0.1
# Good for WSL:  LocalAddress = 0.0.0.0
```

### Fix A — Bind to all interfaces (what we used)

1. Edit `C:\Users\cjfit\.lmstudio\.internal\http-server-config.json`:

```json
"networkInterface": "0.0.0.0"
```

2. Restart server via CLI:

```powershell
lms server stop
lms server start --bind 0.0.0.0
```

3. Verify from WSL:

```bash
curl http://172.28.112.1:1234/v1/models
```

**Security:** `0.0.0.0` exposes the API on your LAN. Fine for home use; enable LM Studio auth on shared networks.

### Fix B — WSL mirrored networking (alternative)

Create `C:\Users\cjfit\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Then run `wsl --shutdown` and reopen WSL. LM Studio can stay on `127.0.0.1` and WSL can use `http://127.0.0.1:1234/v1`.

---

## Verify Pi + Qwen

```bash
source ~/.bashrc
export PATH="$HOME/.bun/bin:$PATH"

# List models (needs LM Studio reachable)
pi --list-models

# Quick non-interactive test (~30s first run)
pi -p --provider lmstudio --model qwen/qwen3.8-27b --thinking low --no-tools "Reply exactly: pi-ok"
# Expected: pi-ok

# Or use repo script
~/repos/random-general-repo-cursor-remote-control/scripts/pi-smoke-test.sh
```

### Interactive session

```bash
cd ~/repos/random-general-repo-cursor-remote-control
pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium
```

Inside Pi:

- `/model` — switch models
- `/handoff` — hand session to TelePi (after TelePi setup)

---

## TelePi (Telegram from phone)

### Prerequisites

1. **Telegram bot token** from [@BotFather](https://t.me/BotFather) (`/newbot`)
2. **Your numeric Telegram user ID** from [@userinfobot](https://t.me/userinfobot)
3. Pi working locally (smoke test passes)

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

Config written to: `~/.config/telepi/config.env`

Example template: `~/.config/telepi/config.env.example`

### Keep TelePi running after logout

```bash
loginctl enable-linger "$USER"
systemctl --user status telepi.service
telepi status
```

### Daily use

1. Start Pi in your repo: `pi`
2. Run `/handoff` inside Pi
3. Open Telegram → your bot → `/start`
4. Send prompts from phone (text, voice, images supported)
5. `/handback` in Telegram to resume in terminal

---

## After reboot checklist

1. **LM Studio** — load Qwen 3.8 27B, start server with `--bind 0.0.0.0` if needed
2. **Check WSL gateway IP** — may change: `ip route show default | awk '{print $3}'`
3. **Update `~/.pi/agent/models.json`** if IP changed
4. **Test:** `curl http://<gateway-ip>:1234/v1/models`
5. **TelePi service:** `systemctl --user status telepi.service`

---

## Repo helper scripts

| Script | Purpose |
|--------|---------|
| `scripts/setup-pi-telepi-wsl.sh` | Install/configure Pi + TelePi + LM Studio URLs |
| `scripts/detect-lmstudio-host.sh` | Find reachable LM Studio host from WSL |
| `scripts/pi-smoke-test.sh` | curl + `pi --list-models` + quick prompt test |

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `npm error Maximum call stack size exceeded` on `pi install` | Windows npm in WSL | Use `"npmCommand": ["bun"]` in settings.json |
| WSL curl to `:1234` times out | LM Studio on 127.0.0.1 only | Bind `0.0.0.0` (see above) |
| Pi `Request timed out` | LM Studio down, xhigh reasoning, or 8k context | Start server, set medium/low reasoning, 32k+ context |
| `pi` not found | PATH | `source ~/.bashrc` or `export PATH="$HOME/.bun/bin:$PATH"` |
| Model ID mismatch | Wrong id in models.json | Match output of `curl .../v1/models` exactly |
| TelePi bot silent | Service not running / wrong token | `telepi status`, check `config.env` |

---

## Harness choice (why Pi?)

We evaluated Goose, OpenCode, Oh My Pi, and Pi for **local Qwen 3.8 27B + Telegram**:

- **Pi** — proven with Qwen 3.8 27B + LM Studio (Simon Willison); minimal harness, best for 27B local
- **TelePi** — Telegram bridge for Pi (third-party, works well)
- **Goose** — built-in Telegram, but more LM Studio + Qwen friction; good fallback
- **Oh My Pi** — Pi++ with 32 tools; heavier, unproven with 3.8 27B locally

This setup uses **Pi + TelePi**.

---

## Key file paths (quick reference)

| What | Path |
|------|------|
| Pi config | `~/.pi/agent/` |
| LM Studio server config | `C:\Users\cjfit\.lmstudio\.internal\http-server-config.json` |
| LM Studio CLI | `C:\Users\cjfit\.lmstudio\bin\lms.exe` |
| TelePi config | `~/.config/telepi/config.env` |
| Default workspace | `/home/chris/repos/random-general-repo-cursor-remote-control` |
