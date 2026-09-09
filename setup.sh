#!/bin/bash
set -euo pipefail

# Create the repo-local .venv and install Python dependencies from requirements.txt.
# Lightweight, deps-only setup; for interactive gobcron configuration use bin/init.sh.

SCRIPTDIR="$(dirname "$(realpath "${BASH_SOURCE[0]}")")"
cd "$SCRIPTDIR"

printf "creating python venv... "
python3 -m venv .venv
echo -e '\E[32m'"\033[1m[ok]\033[0m"

printf "installing dependencies from requirements.txt... "
.venv/bin/pip install --quiet --upgrade pip
.venv/bin/pip install --quiet -r requirements.txt
echo -e '\E[32m'"\033[1m[ok]\033[0m"

echo "Done. Run scripts as: .venv/bin/python3 bin/<script>.py"
