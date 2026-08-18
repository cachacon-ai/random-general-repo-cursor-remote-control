# Local Agent Setup: Pi + LM Studio + Qwen 3.8 27B + TelePi (WSL)

Guide for running a **local coding agent** on Windows/WSL using:

- **LM Studio** — serves Qwen 3.8 27B locally
- **Pi** — minimal agent harness (tool loop)
- **TelePi** — Telegram bridge for phone access

Tested on WSL2 (Ubuntu) with LM Studio on Windows host.

---

## Recommended stack

```text
LM Studio (Qwen 3.8 27B on Windows)
        ↓
       Pi (in WSL)
        ↓
     TelePi (Telegram on phone)
```

**Why Pi (not Goose / Oh My Pi)?**

- Qwen 3.8 27B + LM Studio is **proven on vanilla Pi** (minimal system prompt = more context for local 27B).
- Goose has built-in Telegram but more friction with LM Studio + Qwen tool loops.
- Oh My Pi is Pi++ (32 tools); heavier and unproven with local 27B — upgrade later if Pi feels too bare.

---

## Why Windows native install failed

The `curl -fsSL https://pi.dev/install.sh | bash` path failed because this environment mixes:

- **Linux Node** (Cursor/WSL)
- **Windows npm** (`/mnt/c/Program Files/nodejs/npm`)

That breaks `pi install` with `Maximum call stack size exceeded`.

**Fix:** Install and run **Pi in WSL using Bun**, not Windows npm.

---

## Prerequisites

- Windows 11 + WSL2 (Ubuntu)
- LM Studio on Windows with **qwen/qwen3.8-27b** downloaded
- Bun (installed to `~/.bun` via https://bun.sh)
- Node 22.19+ (for Pi engine requirement; Bun satisfies runtime)

---

## One-time install (WSL)

```bash
source ~/.bashrc
export PATH="$HOME/.bun/bin:$PATH"

# Install Bun if missing
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc

# Install Pi + TelePi
bun install -g @earendil-works/pi-coding-agent
bun install -g @futurelab-studio/telepi

# Verify
pi --version    # e.g. 0.84.2
telepi version  # e.g. 0.4.2
```

Or run the repo setup script:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/setup-pi-telepi-wsl.sh
```

### pi-lmstudio extension

`pi install npm:pi-lmstudio` fails on this machine (Windows npm). Install manually with Bun:

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

### Load the model

1. Open **LM Studio** on Windows.
2. Load **qwen/qwen3.8-27b**.
3. **Developer tab → Start Server** (port 1234 default).

### Critical settings

| Setting | Recommendation |
|---------|----------------|
| Context length | **32k minimum** (not 8k default) |
| Reasoning effort | **medium** or **low** (not xhigh — burns tokens/time) |
| Preserve thinking | OK for agents, but eats context on long sessions |

### WSL networking fix (required)

By default LM Studio binds to **`127.0.0.1` only**. WSL **cannot** reach Windows localhost on default NAT networking.

**Symptom:** LM Studio running, but from WSL `curl http://172.28.112.1:1234/v1/models` times out.

**Fix A — Bind to all interfaces (what we used):**

Edit `C:\Users\<you>\.lmstudio\.internal\http-server-config.json`:

```json
{
  "networkInterface": "0.0.0.0",
  "port": 1234
}
```

Restart server from PowerShell or WSL:

```powershell
lms server stop
lms server start --bind 0.0.0.0
```

Or from WSL:

```bash
/mnt/c/Users/<you>/.lmstudio/bin/lms.exe server stop
/mnt/c/Users/<you>/.lmstudio/bin/lms.exe server start --bind 0.0.0.0
```

Verify from WSL:

```bash
HOST=$(ip route show default | awk '{print $3}')
curl "http://${HOST}:1234/v1/models"
```

**Fix B — WSL mirrored networking (alternative):**

Create `C:\Users\<you>\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Run `wsl --shutdown`, reopen WSL. Then Pi can use `http://127.0.0.1:1234/v1`.

**Security:** `0.0.0.0` exposes LM Studio to your LAN. Fine for home; enable LM Studio auth on shared networks.

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

Replace `172.28.112.1` with your WSL gateway IP (`ip route show default | awk '{print $3}'`):

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

Use `"api": "openai-responses"` if your LM Studio build supports `/v1/responses` and chat completions misbehave.

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

## Smoke test

```bash
export PATH="$HOME/.bun/bin:$PATH"
cd ~/repos/random-general-repo-cursor-remote-control

# List models (uses pi-lmstudio discovery)
pi --list-models

# One-shot test (first run may take 30–90s on 27B)
pi -p --provider lmstudio --model qwen/qwen3.8-27b --thinking low --no-tools "Reply exactly: pi-ok"

# Interactive session
pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium
```

Repo script:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/pi-smoke-test.sh
```

Inside Pi: `/model` to switch models.

---

## TelePi (Telegram)

### Prerequisites

1. **Bot token** — [@BotFather](https://t.me/BotFather) → `/newbot`
2. **Your Telegram user ID** — [@userinfobot](https://t.me/userinfobot) (numeric)
3. Pi working locally first (smoke test above)

### Setup (WSL)

```bash
export PATH="$HOME/.bun/bin:$PATH"
telepi setup
```

Prompts for:

- `TELEGRAM_BOT_TOKEN`
- `TELEGRAM_ALLOWED_USER_IDS` (your numeric ID)
- `DEFAULT_WORKSPACE` → e.g. `/home/chris/repos/random-general-repo-cursor-remote-control`

Non-interactive:

```bash
telepi setup "YOUR_BOT_TOKEN" "YOUR_TELEGRAM_ID" "/home/chris/repos/random-general-repo-cursor-remote-control"
```

Config file: `~/.config/telepi/config.env`

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
4. Send prompts from phone
5. `/handback` in Telegram to resume in terminal

---

## Repo scripts

| Script | Purpose |
|--------|---------|
| `scripts/setup-pi-telepi-wsl.sh` | Install Pi/TelePi, write config, detect LM Studio host |
| `scripts/detect-lmstudio-host.sh` | Find reachable LM Studio IP from WSL |
| `scripts/pi-smoke-test.sh` | curl + `pi --list-models` + one-shot prompt |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `pi` not found | `source ~/.bashrc` or `export PATH="$HOME/.bun/bin:$PATH"` |
| `pi install` npm stack overflow | Use `"npmCommand": ["bun"]` in settings.json; install extensions with `bun add` |
| WSL can't reach LM Studio | Bind server to `0.0.0.0` (see above) or enable WSL mirrored networking |
| Pi request timeout | LM Studio not running; model on xhigh reasoning; context too small |
| Tools don't execute | Try `--thinking low`; confirm model ID matches `curl .../v1/models` |
| Gateway IP changed after reboot | Re-run `detect-lmstudio-host.sh`; update `models.json` baseUrl |
| TelePi bot silent | `telepi status`; check allowlist IDs; `systemctl --user restart telepi` |

---

## Paths reference (this machine)

| Item | Path |
|------|------|
| Pi binary | `~/.bun/bin/pi` |
| TelePi binary | `~/.bun/bin/telepi` |
| Pi config | `~/.pi/agent/` |
| TelePi config | `~/.config/telepi/config.env` |
| LM Studio server config | `C:\Users\cjfit\.lmstudio\.internal\http-server-config.json` |
| LM Studio CLI | `C:\Users\cjfit\.lmstudio\bin\lms.exe` |
| WSL gateway IP (current) | `172.28.112.1` (may change — detect dynamically) |

---

## Alternatives considered (for context)

| Tool | Telegram | Local Qwen 3.8 | Notes |
|------|----------|----------------|-------|
| **Pi + TelePi** | via TelePi | ✅ proven | **Chosen stack** |
| Goose | built-in | ⚠️ some LM Studio friction | Good if Telegram zero-config matters more |
| Oh My Pi | extensions | unproven on 27B | Upgrade path from Pi |
| OpenClaw | built-in | ✅ | Heavier personal-assistant style |
| Cursor remote | iOS app | N/A | Different use case (Cursor agents) |

---

## After reboot checklist

1. Start LM Studio on Windows; load qwen3.8-27b
2. `lms server start --bind 0.0.0.0` (if GUI resets to localhost-only)
3. From WSL: `curl http://$(ip route show default | awk '{print $3}'):1234/v1/models`
4. `pi --list-models` then start session
5. TelePi: `telepi status` (systemd user service should auto-start if configured)
