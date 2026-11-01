#!/usr/bin/env bash
# One-command local start.
set -e
cd "$(dirname "$0")"
[ -d .venv ] || python3 -m venv .venv
./.venv/bin/pip install -q -r requirements.txt
echo "→ console:  http://localhost:8000/console"
echo "→ client:   $(python3 tools/switch_client.py --list | sed -n 's/^  \\([a-z_]*\\) .*/\\1/p' | head -1) available — switch with python3 tools/switch_client.py <name>"
exec ./.venv/bin/uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}"
