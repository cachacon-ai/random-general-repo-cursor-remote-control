#!/usr/bin/env bash
set -euo pipefail

# Best-effort WSL -> Windows host IP for LM Studio.
if [[ -n "${LMSTUDIO_HOST:-}" ]]; then
  echo "$LMSTUDIO_HOST"
  exit 0
fi

default_gw="$(ip route show default 2>/dev/null | awk '{print $3}' | head -1)"
if [[ -n "$default_gw" ]] && curl -sf --connect-timeout 2 "http://${default_gw}:1234/v1/models" >/dev/null 2>&1; then
  echo "$default_gw"
  exit 0
fi

resolv="$(awk '/nameserver/ {print $2; exit}' /etc/resolv.conf 2>/dev/null || true)"
if [[ -n "$resolv" ]] && curl -sf --connect-timeout 2 "http://${resolv}:1234/v1/models" >/dev/null 2>&1; then
  echo "$resolv"
  exit 0
fi

if curl -sf --connect-timeout 2 "http://127.0.0.1:1234/v1/models" >/dev/null 2>&1; then
  echo "127.0.0.1"
  exit 0
fi

echo "$default_gw" >&2
exit 1
