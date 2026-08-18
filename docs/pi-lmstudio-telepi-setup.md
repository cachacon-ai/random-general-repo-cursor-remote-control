# Pi + LM Studio + TelePi Setup (WSL on Windows)

Guide for running a **local coding agent** with **Qwen 3.8 27B** in LM Studio, **Pi** as the agent harness, and **TelePi** for Telegram access from your phone.

Written for this machine: **Windows host + WSL2 (Ubuntu)**.

---

## Recommended stack

```text
LM Studio (Qwen 3.8 27B on Windows)
        ↓
       Pi  (agent harness in WSL)
        ↓
     TelePi  (Telegram bridge)
```

Why this stack:

- **Pi** — minimal harness; proven with Qwen 3.8 27B + tool calling
- **LM Studio** — you already have Qwen models here
- **TelePi** — Telegram bridge for Pi (not built into Pi itself)

Alternatives we considered and skipped for now:

| Option | Why not (for now) |
|--------|-------------------|
| Goose | Built-in Telegram, but more friction with LM Studio + Qwen tool loops |
| Oh My Pi | Heavier harness; no public Qwen 3.8 27B validation |
| OpenClaw | Better for WhatsApp/iMessage; overkill if Telegram is enough |
| Cursor remote agent | Different product — cloud/private worker, not local Qwen |

---

## Why the Windows `curl | bash` install failed

The one-liner from pi.dev failed because this environment mixes:

- **Linux Node** (Cursor/WSL)
- **Windows npm** (`/mnt/c/Program Files/nodejs/npm`)

That combination causes `npm error Maximum call stack size exceeded`.

**Fix:** Install and run Pi in **WSL using Bun**, not Windows npm.

---

## Prerequisites

- Windows with **LM Studio** installed
- **WSL2** (Ubuntu) with network access to Windows host
- Enough RAM/VRAM for Qwen 3.8 27B (Q4 ~17GB model + context)

---

## Part 1 — Install Pi and TelePi in WSL

### 1. Ensure Bun is on PATH

Bun should already be in `~/.bashrc`:

```bash
export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"
source ~/.bashrc
```

### 2. Install Pi coding agent

```bash
bun install -g @earendil-works/pi-coding-agent
pi --version   # expect 0.84.x
```

Do **not** use `curl -fsSL https://pi.dev/install.sh | bash` on this machine.

### 3. Install pi-lmstudio extension

Pi's `pi install npm:pi-lmstudio` may fail if it invokes Windows npm. Use Bun instead:

```bash
mkdir -p ~/.pi/agent/npm
cd ~/.pi/agent/npm
bun init -y
bun add pi-lmstudio
```

Register the package in Pi settings (see Part 3).

### 4. Install TelePi

```bash
bun install -g @futurelab-studio/telepi
telepi version   # expect 0.4.x
```

### 5. Or run the repo setup script

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/setup-pi-telepi-wsl.sh
```

---

## Part 2 — LM Studio on Windows

### Load the model

1. Open **LM Studio** on Windows
2. Load **qwen/qwen3.8-27b**
3. Use a quant that fits your hardware (Q4_K_M ~17GB is common)

### Critical model settings

| Setting | Recommendation |
|---------|----------------|
| **Context length** | **32k minimum** (not default 8k) |
| **Reasoning effort** | **medium** or **low** (not default xhigh) |
| **Preserve thinking** | OK for agents, but eats context on long sessions |

Default `xhigh` reasoning can burn tens of thousands of tokens before doing anything useful.

### Start the server

**Developer tab → Start Server** (or use CLI below).

---

## Part 3 — WSL ↔ LM Studio networking (IMPORTANT)

### The problem

By default LM Studio binds to **`127.0.0.1:1234`** (Windows localhost only). WSL **cannot** reach that address — connections time out even when LM Studio is running.

Verify from WSL:

```bash
curl --connect-timeout 5 http://172.28.112.1:1234/v1/models
```

If it times out, the server is localhost-only.

### Fix A — Bind LM Studio to all interfaces (what we used)

Edit Windows config:

```
C:\Users\cjfit\.lmstudio\.internal\http-server-config.json
```

Change:

```json
"networkInterface": "0.0.0.0"
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

**Security:** `0.0.0.0` exposes the API on your LAN. Fine for home use; enable LM Studio auth on shared networks.

### Fix B — WSL mirrored networking (alternative)

Create `C:\Users\cjfit\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Then:

```powershell
wsl --shutdown
```

Reopen WSL. Pi may then use `http://127.0.0.1:1234/v1` directly.

### Find the Windows host IP from WSL

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/detect-lmstudio-host.sh
# usually: 172.28.112.1 (default gateway — can change after reboot)
ip route show default | awk '{print $3}'
```

---

## Part 4 — Pi configuration files

All paths under `~/.pi/agent/` in WSL.

### `settings.json`

Uses Bun for package installs (avoids broken Windows npm):

```json
{
  "npmCommand": ["bun"],
  "packages": ["npm:pi-lmstudio"],
  "shellPath": "/bin/bash"
}
```

### `models.json`

Replace `172.28.112.1` with your current WSL gateway if needed:

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

Notes:

- Use **`openai-completions`** for LM Studio (we had timeouts with `openai-responses` in some tests)
- Model `id` must match LM Studio exactly — check with `curl http://<host>:1234/v1/models`

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

LM Studio ignores the key; Pi still requires a non-empty value.

---

## Part 5 — Verify Pi works

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

### Smoke test (no tools, low thinking)

```bash
cd ~/repos/random-general-repo-cursor-remote-control
pi -p --provider lmstudio --model qwen/qwen3.8-27b --thinking low --no-tools "Reply with exactly: pi-ok"
```

Or use the script:

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
- `/help` — commands

### Test tool calling

Ask Pi to list files or read README. Confirm it actually runs tools, not just describes what it would do.

---

## Part 6 — TelePi (Telegram)

### Prerequisites

1. **Telegram bot token** — [@BotFather](https://t.me/BotFather) → `/newbot`
2. **Your Telegram user ID** — [@userinfobot](https://t.me/userinfobot) (numeric)
3. Pi working locally first

### Setup

Interactive:

```bash
telepi setup
```

Non-interactive:

```bash
telepi setup "YOUR_BOT_TOKEN" "YOUR_TELEGRAM_ID" "/home/chris/repos/random-general-repo-cursor-remote-control"
```

Config file location:

```text
~/.config/telepi/config.env
```

Example:

```bash
TELEGRAM_BOT_TOKEN=123456789:AAF...
TELEGRAM_ALLOWED_USER_IDS=111111111
DEFAULT_WORKSPACE=/home/chris/repos/random-general-repo-cursor-remote-control
```

Template also at: `~/.config/telepi/config.env.example`

### Keep TelePi running after logout

```bash
loginctl enable-linger "$USER"
systemctl --user status telepi.service
systemctl --user restart telepi.service   # if needed
```

### Daily usage

1. Start Pi in your repo: `pi`
2. Run `/handoff` inside Pi
3. Open Telegram → your bot → `/start`
4. Send prompts from phone (text, voice, images supported)
5. `/handback` in Telegram to resume in terminal

Check status:

```bash
telepi status
```

---

## Part 7 — After reboot checklist

1. **Start LM Studio** on Windows and load Qwen 3.8 27B
2. **Start server** with network bind:
   ```bash
   /mnt/c/Users/cjfit/.lmstudio/bin/lms.exe server start --bind 0.0.0.0
   ```
3. **Verify from WSL:**
   ```bash
   curl http://172.28.112.1:1234/v1/models
   ```
4. **Re-check gateway IP** if WSL networking changed:
   ```bash
   scripts/detect-lmstudio-host.sh
   ```
   Update `~/.pi/agent/models.json` if IP changed.
5. **TelePi** should auto-start if systemd user service is enabled.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| WSL curl to `:1234` times out | LM Studio on `127.0.0.1` only | Bind `0.0.0.0` (Part 3) |
| Pi `Request timed out` | LM Studio down, xhigh reasoning, or wrong API mode | Start server; use `--thinking low`; try `openai-completions` |
| `pi install` npm stack overflow | Windows npm in WSL | Use `"npmCommand": ["bun"]` in settings.json |
| Tools don't execute | Model/config issue | Lower reasoning; confirm tool-capable Qwen; check LM Studio logs |
| `pi` command not found | PATH | `source ~/.bashrc` or `export PATH="$HOME/.bun/bin:$PATH"` |
| Gateway IP changed | WSL restart | Re-run `detect-lmstudio-host.sh`, update `models.json` |
| TelePi bot silent | Service not running / wrong token | `telepi status`; check `config.env` |

---

## Repo scripts

| Script | Purpose |
|--------|---------|
| `scripts/setup-pi-telepi-wsl.sh` | Install Pi, pi-lmstudio, TelePi; write config |
| `scripts/detect-lmstudio-host.sh` | Find reachable LM Studio host IP from WSL |
| `scripts/pi-smoke-test.sh` | curl + `pi --list-models` + quick prompt test |

---

## Installed binary locations (WSL)

| Tool | Path |
|------|------|
| Pi | `~/.bun/bin/pi` |
| TelePi | `~/.bun/bin/telepi` |
| Bun | `~/.bun/bin/bun` |
| lms (Windows) | `/mnt/c/Users/cjfit/.lmstudio/bin/lms.exe` |

---

## References

- Pi: https://pi.dev / https://github.com/badlogic/pi-mono
- pi-lmstudio: https://www.npmjs.com/package/pi-lmstudio
- TelePi: https://github.com/williamleong/TelePi
- LM Studio serve on network: https://lmstudio.ai/docs/developer/core/server/serve-on-network
- Simon Willison on Qwen 3.8 27B + Pi: https://simonwillison.net/2026/Aug/16/qwen-38-27b/
