# random-general-repo-cursor-remote-control

Scratch repo for Cursor **Remote Control** and **Cloud Agents** testing.

This folder exists so Cursor can attach a Git-backed workspace with a GitHub remote when steering agents from the iOS app.

## Usage

1. Open this folder in Cursor (Agents Window).
2. Enable **Settings → Agents → Remote Control**.
3. Run `/remote-control`, then send a follow-up message.
4. Continue the session from the Cursor iOS app inbox.

## Remote Control on Windows (WSL worker)

Native Windows Remote Control workers currently crash on some builds (`better-sqlite3` Node ABI mismatch). Use the WSL worker instead:

1. Start the worker (leave this running):
   ```powershell
   C:\Users\cjfit\cursor-wsl-worker.cmd
   ```
   Or inside WSL:
   ```bash
   ~/repos/random-general-repo-cursor-remote-control/scripts/start-wsl-cursor-worker.sh
   ```

2. In Cursor desktop, open the **WSL copy** of this repo (not the OneDrive path):
   ```
   \\wsl$\Ubuntu\home\chris\repos\random-general-repo-cursor-remote-control
   ```

3. Agents Window → enable Remote Control → `/remote-control` → send a follow-up.

4. Continue from the Cursor iOS app inbox.

Worker dashboard: https://cursor.com/agents

## Local agent (Pi + LM Studio + TelePi)

For a **local Qwen 3.8 27B agent** in WSL with **Telegram** phone access, see **[LOCAL-AGENT-SETUP.md](LOCAL-AGENT-SETUP.md)** (Pi harness, LM Studio on Windows, TelePi bridge, WSL networking fix).

Quick start (WSL):

```bash
~/repos/random-general-repo-cursor-remote-control/scripts/setup-pi-telepi-wsl.sh
~/repos/random-general-repo-cursor-remote-control/scripts/pi-smoke-test.sh
telepi setup
```
