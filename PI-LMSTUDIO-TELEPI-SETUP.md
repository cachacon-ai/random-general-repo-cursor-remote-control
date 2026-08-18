# Pi + LM Studio + Qwen 3.8 27B + TelePi (WSL on Windows)

Local coding agent stack: **Pi** (harness) → **LM Studio** (Qwen 3.8 27B) → **TelePi** (Telegram from phone).

This guide reflects setup performed on **WSL2 (Ubuntu)** with **LM Studio on Windows**. Pi and TelePi run in WSL; the model runs on Windows.

---

## Recommended stack (summary)

| Layer | Tool |
|-------|------|
| Model | Qwen 3.8 27B in LM Studio |
| Harness | Pi (`@earendil-works/pi-coding-agent`) |
| LM Studio bridge | `pi-lmstudio` extension |
| Phone | TelePi (`@futurelab-studio/telepi`) |

**Why not native Windows Pi?** The `curl \| bash` installer from pi.dev failed, and `pi install` broke because WSL was using **Linux Node** with **Windows npm** (`/mnt/c/Program Files/nodejs/npm`). Use **WSL + Bun** instead.

**Why Pi over Goose / Oh My Pi?** Qwen 3.8 27B + LM Studio is **proven on Pi** (minimal harness). Goose has built-in Telegram but more LM Studio/Qwen friction. Oh My Pi is heavier and unproven with 3.8 27B locally.

---

## What’s installed (paths)

| Tool | Location | Version (at setup) |
|------|----------|---------------------|
| Bun | `~/.bun/bin/bun` | 1.3.14 |
| Pi | `~/.bun/bin/pi` | 0.84.2 |
| TelePi | `~/.bun/bin/telepi` | 0.4.2 |
| pi-lmstudio | `~/.pi/agent/npm/node_modules/pi-lmstudio` | 1.5.0 |

Config files:

- `~/.pi/agent/settings.json` — Pi settings (`npmCommand: ["bun"]`, packages)
- `~/.pi/agent/models.json` — LM Studio provider + Qwen model
- `~/.pi/agent/lmstudio.json` — LM Studio URL(s)
- `~/.pi/agent/auth.json` — LM Studio API key placeholder
- `~/.config/telepi/config.env` — TelePi secrets (create via `telepi setup`)
- `~/.config/telepi/config.env.example` — template

Repo helper scripts:

- `scripts/setup-pi-telepi-wsl.sh` — (re)install and write config
- `scripts/detect-lmstudio-host.sh` — find reachable LM Studio host from WSL
- `scripts/pi-smoke-test.sh` — connectivity + one-shot Pi prompt

---

## Step 0: Shell PATH

In any **new WSL terminal**:

```bash
source ~/.bashrc
export PATH="$HOME/.bun/bin:$PATH"
pi --version
telepi version
```

If missing, re-run `scripts/setup-pi-telepi-wsl.sh`.

---

## Step 1: Install (WSL) — if starting fresh

```bash
# Bun (if needed)
curl -fsSL https://bun.sh/install | bash
source ~/.bashrc

# Pi (do NOT use pi.dev install.sh on this machine)
bun install -g @earendil-works/pi-coding-agent

# pi-lmstudio (if pi install fails due to Windows npm)
mkdir -p ~/.pi/agent/npm
cd ~/.pi/agent/npm && bun init -y && bun add pi-lmstudio

# TelePi
bun install -g @futurelab-studio/telepi
```

Register extension in `~/.pi/agent/settings.json`:

```json
{
  "npmCommand": ["bun"],
  "packages": ["npm:pi-lmstudio"],
  "shellPath": "/bin/bash"
}
```

Or run the repo script:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/setup-pi-telepi-wsl.sh
```

---

## Step 2: LM Studio on Windows

1. Open **LM Studio** on Windows (not inside WSL).
2. Load **qwen/qwen3.8-27b**.
3. **Developer tab → Start Server** (or use CLI below).
4. **Context:** 32k minimum (not 8192 — Qwen thinking will consume it).
5. **Reasoning effort:** **medium** or **low** (default `xhigh` is extremely slow).

### Critical: WSL cannot reach `127.0.0.1` on Windows

By default LM Studio binds to **`127.0.0.1:1234`** only. WSL is a separate network namespace and **cannot** connect until the server listens on all interfaces.

**Fix A — Bind to all interfaces (used during setup):**

Edit `C:\Users\cjfit\.lmstudio\.internal\http-server-config.json`:

```json
"networkInterface": "0.0.0.0"
```

Then restart the server:

```powershell
lms server stop
lms server start --bind 0.0.0.0
```

**Fix B — WSL mirrored networking (alternative, keeps LM Studio on localhost):**

Create `C:\Users\cjfit\.wslconfig`:

```ini
[wsl2]
networkingMode=mirrored
```

Then from PowerShell: `wsl --shutdown`, reopen WSL. Pi can then use `http://127.0.0.1:1234/v1`.

**Security:** `0.0.0.0` exposes the API on your LAN. Fine at home; enable LM Studio auth on shared networks.

### Test from WSL

```bash
# Detect Windows host IP (usually default gateway)
LM_HOST=$(ip route show default | awk '{print $3}')
echo "$LM_HOST"
curl "http://${LM_HOST}:1234/v1/models"
```

Or:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/detect-lmstudio-host.sh
```

---

## Step 3: Pi model config

`~/.pi/agent/models.json` (update `baseUrl` if gateway IP changes after reboot):

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

`~/.pi/agent/auth.json`:

```json
{
  "lmstudio": {
    "type": "api_key",
    "key": "lm-studio"
  }
}
```

Get exact model id from:

```bash
curl "http://$(ip route show default | awk '{print $3}'):1234/v1/models"
```

---

## Step 4: Smoke test Pi

```bash
cd ~/repos/random-general-repo-cursor-remote-control
pi --list-models
# expect: lmstudio  qwen/qwen3.8-27b

pi -p --provider lmstudio --model qwen/qwen3.8-27b --thinking low --no-tools "Reply exactly: pi-ok"
# expect: pi-ok (first run may take 30–90s)
```

Or:

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/pi-smoke-test.sh
```

Interactive session:

```bash
pi --provider lmstudio --model qwen/qwen3.8-27b --thinking medium
# inside Pi: /model to switch models
```

---

## Step 5: TelePi (Telegram)

### A. Create bot

1. Message [@BotFather](https://t.me/BotFather) → `/newbot`
2. Copy the **bot token**

### B. Get your Telegram user ID

1. Message [@userinfobot](https://t.me/userinfobot)
2. Copy your **numeric ID**

### C. Run setup (WSL)

Interactive:

```bash
telepi setup
```

Non-interactive:

```bash
telepi setup "YOUR_BOT_TOKEN" "YOUR_TELEGRAM_ID" "/home/chris/repos/random-general-repo-cursor-remote-control"
```

Config lives at `~/.config/telepi/config.env`:

```bash
TELEGRAM_BOT_TOKEN=...
TELEGRAM_ALLOWED_USER_IDS=...
DEFAULT_WORKSPACE=/home/chris/repos/random-general-repo-cursor-remote-control
```

### D. Keep TelePi running after logout

```bash
loginctl enable-linger "$USER"
systemctl --user status telepi.service
telepi status
```

### E. Daily use

1. WSL: `cd ~/repos/random-general-repo-cursor-remote-control && pi`
2. In Pi: `/handoff`
3. Telegram → your bot → `/start`
4. Send prompts from phone
5. `/handback` in Telegram to resume in terminal

---

## After reboot checklist

1. Start LM Studio and load Qwen 3.8 27B.
2. Ensure server is bound for WSL:
   ```powershell
   lms server start --bind 0.0.0.0
   ```
3. From WSL: `curl http://$(ip route show default | awk '{print $3}'):1234/v1/models`
4. If gateway IP changed, update `~/.pi/agent/models.json` `baseUrl` or re-run `scripts/setup-pi-telepi-wsl.sh`.
5. Check TelePi: `telepi status` (restart with `systemctl --user restart telepi.service` if needed).

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `curl :1234` times out from WSL | LM Studio on `127.0.0.1` only | Bind `0.0.0.0` or enable WSL mirrored networking |
| `pi install` / npm stack overflow | Windows npm in WSL | Use `"npmCommand": ["bun"]` in settings.json |
| Pi `Request timed out` | LM Studio down, xhigh reasoning, or wrong API | Start server; use `--thinking low`; check `openai-completions` |
| `pi` not found | PATH | `source ~/.bashrc` or `export PATH="$HOME/.bun/bin:$PATH"` |
| Model id mismatch | Wrong id in models.json | `curl .../v1/models` and copy exact id |
| TelePi no response | Service not running | `telepi status`, `systemctl --user restart telepi.service` |

---

## Harness comparison (reference)

| | Pi | Goose | Oh My Pi |
|---|-----|-------|----------|
| Qwen 3.8 27B + LM Studio | Proven | Possible, more friction | Unproven locally |
| Telegram | TelePi (add-on) | Built-in gateway | Extension (omp-telegram) |
| Harness weight | Minimal | Medium | Heavy (32 tools) |

---

## Related: Cursor Remote Control

This repo also documents Cursor Cloud Agent remote control. See `README.md` for WSL worker setup. That is separate from the Pi/TelePi local agent stack.
