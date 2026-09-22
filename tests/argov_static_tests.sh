#!/usr/bin/env bash
set -euo pipefail

SCRIPT="${1:-argov.sh}"

if [ ! -f "$SCRIPT" ]; then
  echo "missing script: $SCRIPT" >&2
  exit 1
fi

BASH_BIN="${BASH:-bash}"
"$BASH_BIN" -n "$SCRIPT"
PYTHON_BIN=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && "$candidate" -c 'import sys' >/dev/null 2>&1; then
    PYTHON_BIN="$(command -v "$candidate")"
    break
  fi
done
if [ -z "$PYTHON_BIN" ]; then
  echo "python3 or python is required for static tests" >&2
  exit 1
fi
"$PYTHON_BIN" tests/argov_static_tests.py "$SCRIPT"
"$PYTHON_BIN" tests/argov_compat_tests.py
"$PYTHON_BIN" tests/argov_subscription_tests.py "$SCRIPT"
"$PYTHON_BIN" tests/argov_user_migration_tests.py "$SCRIPT"

if ! grep -q 'StandardOutput=append:${TUNNEL_LOG}' "$SCRIPT"; then
  echo "systemd temp tunnel service must append stdout to TUNNEL_LOG" >&2
  exit 1
fi

if ! grep -q 'StandardError=append:${TUNNEL_LOG}' "$SCRIPT"; then
  echo "systemd temp tunnel service must append stderr to TUNNEL_LOG so get_argo_domain can read cloudflared URLs" >&2
  exit 1
fi

echo "argov static tests passed"
