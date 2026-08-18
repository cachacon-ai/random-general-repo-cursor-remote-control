# random-general-repo-cursor-remote-control

Scratch repo for Cursor **Remote Control** and **Cloud Agents** testing.

This folder exists so Cursor can attach a Git-backed workspace with a GitHub remote when steering agents from the iOS app.

## Usage

1. Open this folder in Cursor (Agents Window).
2. Enable **Settings → Agents → Remote Control**.
3. Run `/remote-control`, then send a follow-up message.
4. Continue the session from the Cursor iOS app inbox.

## Notes

- Keep at least one commit on `main` so the remote stays valid.
- On Windows, Remote Control may require the WSL worker workaround until the native worker package is fixed.
