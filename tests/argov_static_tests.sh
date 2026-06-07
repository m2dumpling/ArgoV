#!/usr/bin/env bash
set -euo pipefail

SCRIPT="${1:-argov.sh}"

if [ ! -f "$SCRIPT" ]; then
  echo "missing script: $SCRIPT" >&2
  exit 1
fi

bash -n "$SCRIPT"
PYTHON_BIN="$(command -v python3 || command -v python || true)"
if [ -z "$PYTHON_BIN" ]; then
  echo "python3 or python is required for static tests" >&2
  exit 1
fi
"$PYTHON_BIN" tests/argov_static_tests.py "$SCRIPT"

if ! grep -q 'StandardOutput=append:${TUNNEL_LOG}' "$SCRIPT"; then
  echo "systemd temp tunnel service must append stdout to TUNNEL_LOG" >&2
  exit 1
fi

if ! grep -q 'StandardError=append:${TUNNEL_LOG}' "$SCRIPT"; then
  echo "systemd temp tunnel service must append stderr to TUNNEL_LOG so get_argo_domain can read cloudflared URLs" >&2
  exit 1
fi

echo "argov static tests passed"
