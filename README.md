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
