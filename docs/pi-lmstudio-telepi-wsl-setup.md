# Pi + LM Studio + Qwen 3.8 27B + TelePi (WSL on Windows)

Local coding agent setup: **Pi** as the harness, **LM Studio** serving **Qwen 3.8 27B** on Windows, **TelePi** for Telegram from your phone. Run Pi and TelePi in **WSL**; run LM Studio on **Windows**.

---

## Why not native Windows / `curl | bash`?

The official installer (`curl -fsSL https://pi.dev/install.sh | bash`) failed because this environment mixes:

- **Linux Node** (Cursor/WSL)
- **Windows npm** (`/mnt/c/Program Files/nodejs/npm`)

That breaks `pi install` with `Maximum call stack size exceeded`.

**Fix:** Install Pi with **Bun** inside WSL:

```bash
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc
bun install -g @earendil-works/pi-coding-agent
```

Use `"npmCommand": ["bun"]` in `~/.pi/agent/settings.json` so `pi install` uses Bun instead of Windows npm.

---

## Quick install (automated)

From this repo in WSL:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/setup-pi-telepi-wsl.sh
```

Scripts included:

| Script | Purpose |
|--------|---------|
| `scripts/setup-pi-telepi-wsl.sh` | Install Pi, pi-lmstudio, TelePi; write config |
| `scripts/detect-lmstudio-host.sh` | Find reachable LM Studio host IP from WSL |
| `scripts/pi-smoke-test.sh` | Test LM Studio + Pi end-to-end |

---

## Manual install

### 1. Bun + Pi + TelePi (WSL)

```bash
source ~/.bashrc
export PATH="$HOME/.bun/bin:$PATH"

bun install -g @earendil-works/pi-coding-agent
bun install -g @futurelab-studio/telepi

pi --version   # expect 0.84.x
telepi version # expect 0.4.x
```

### 2. pi-lmstudio extension

If `pi install npm:pi-lmstudio` fails (Windows npm), install manually:

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

---

## LM Studio (Windows)

### Load model and start server

1. Open **LM Studio** on Windows.
2. Load **qwen/qwen3.8-27b**.
3. **Developer tab → Start Server**.
4. Set **context to 32k+** (not 8192 — Qwen thinking will consume it).
5. Set **reasoning effort to medium or low** (default `xhigh` is extremely slow).

### Critical: WSL cannot reach `127.0.0.1` on Windows

By default LM Studio binds to **`127.0.0.1:1234`** (Windows localhost only). WSL is a separate network namespace and will **timeout** trying to reach it via the WSL gateway IP.

**Symptom:** LM Studio appears running; `curl http://172.x.x.1:1234/v1/models` from WSL times out.

**Verify from Windows PowerShell:**

```powershell
Get-NetTCPConnection -LocalPort 1234 | Select LocalAddress, State
# Bad for WSL:  LocalAddress = 127.0.0.1
# Good for WSL:  LocalAddress = 0.0.0.0
```

### Fix A — Bind to all interfaces (recommended)

Edit `C:\Users\<you>\.lmstudio\.internal\http-server-config.json`:

```json
{
  "networkInterface": "0.0.0.0",
  "port": 1234
}
```

Restart server:

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

### Fix B — WSL mirrored networking (keep LM Studio on localhost)

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
HOST=$(ip route show default | awk '{print $3}')
echo "WSL gateway (Windows host): $HOST"
curl "http://${HOST}:1234/v1/models"
```

---

## Pi configuration

Config directory: `~/.pi/agent/`

### `settings.json`

```json
{
  "npmCommand": ["bun"],
  "packages": ["npm:pi-lmstudio"],
  "shellPath": "/bin/bash"
}
```

### `models.json`

Replace `172.28.112.1` with your WSL gateway IP from `ip route show default`:

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

- Use model `id` exactly as shown by `curl .../v1/models`.
- `openai-completions` worked reliably in testing. `openai-responses` is an alternative if your LM Studio build supports it well.
- If the gateway IP changes after reboot, rerun `scripts/detect-lmstudio-host.sh` and update `baseUrl`.

### `lmstudio.json` (pi-lmstudio extension)

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

LM Studio ignores the key locally; Pi still requires a non-empty value.

---

## Smoke test

```bash
export PATH="$HOME/.bun/bin:$PATH"

pi --list-models
# expect: lmstudio  qwen/qwen3.8-27b

pi -p --provider lmstudio --model qwen/qwen3.8-27b --thinking low --no-tools "Reply exactly: pi-ok"
# expect: pi-ok (may take 30–90s on first run)
```

Or:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/pi-smoke-test.sh
```

### Interactive session

```bash
cd ~/repos/random-general-repo-cursor-remote-control
pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium
```

Inside Pi: `/model` to switch models.

---

## TelePi (Telegram from phone)

### Prerequisites

- Pi working locally (smoke test passes)
- Telegram bot token from [@BotFather](https://t.me/BotFather)
- Your numeric Telegram user ID from [@userinfobot](https://t.me/userinfobot)

### Install (if not already)

```bash
bun install -g @futurelab-studio/telepi
```

### Setup

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

### Keep TelePi running after logout

```bash
loginctl enable-linger "$USER"
systemctl --user status telepi.service
telepi status
```

### Daily use

1. Start LM Studio server on Windows (with `0.0.0.0` bind if using NAT WSL).
2. In WSL: `cd ~/repos/random-general-repo-cursor-remote-control && pi`
3. In Pi: `/handoff`
4. Open Telegram → your bot → `/start`
5. Send prompts from phone
6. `/handback` in Telegram to resume in terminal

---

## After reboot checklist

1. Start LM Studio on Windows; load Qwen 3.8 27B.
2. Start server with network bind:
   ```powershell
   lms server start --bind 0.0.0.0
   ```
3. Confirm WSL gateway IP (may change):
   ```bash
   ip route show default | awk '{print $3}'
   ```
4. Update `~/.pi/agent/models.json` `baseUrl` if IP changed.
5. Test: `curl http://<gateway-ip>:1234/v1/models`
6. TelePi service should auto-start if `telepi setup` was completed; else `telepi status`.

---

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| WSL curl to `:1234` times out | LM Studio on `127.0.0.1` only | Bind `0.0.0.0` or enable WSL mirrored networking |
| `pi install` stack overflow | Windows npm in WSL | Use `"npmCommand": ["bun"]` |
| Pi `Request timed out` | LM Studio down, xhigh reasoning, or wrong IP | Start server, set thinking low/medium, fix baseUrl |
| `pi` not found | PATH | `source ~/.bashrc` or `export PATH="$HOME/.bun/bin:$PATH"` |
| Model id mismatch | Wrong id in models.json | Match `curl .../v1/models` exactly |
| TelePi bot silent | Service not running / wrong token | `telepi status`, check `config.env` |

---

## Architecture

```text
Phone (Telegram)
    ↕ TelePi (WSL, systemd user service)
    ↕ Pi agent (WSL)
    ↕ HTTP OpenAI-compatible API
    ↕ LM Studio (Windows, GPU)
    ↕ Qwen 3.8 27B
```

---

## Harness comparison (why Pi)

| Option | Telegram | Qwen 3.8 27B local | Notes |
|--------|----------|-------------------|-------|
| **Pi + TelePi** | Via TelePi extension | Proven (Simon Willison et al.) | Minimal harness, best for 27B |
| Goose | Built-in gateway | Possible, more friction | Easier phone setup |
| Oh My Pi | Via omp-telegram | Unproven at 32-tool scale | Heavier harness |
| OpenClaw | Built-in | Possible | More "assistant" than coding agent |

---

## Installed versions (as of initial setup)

- Pi (`@earendil-works/pi-coding-agent`): 0.84.2
- pi-lmstudio: 1.5.0
- TelePi (`@futurelab-studio/telepi`): 0.4.2
- Bun: 1.3.14

Binaries: `~/.bun/bin/pi`, `~/.bun/bin/telepi`, `~/.bun/bin/bun`
