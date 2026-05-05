#!/usr/bin/env bash
# deploy.sh – package Lambda dependencies and run Terraform
# Usage: ./deploy.sh [terraform apply flags, e.g. -auto-approve]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── Package Lambda layers (pip install into source dirs) ──────────────────────
for fn in rotation app; do
  dir="$SCRIPT_DIR/lambda/$fn"
  echo ">>> Installing dependencies for $fn Lambda..."
  pip install \
    -r "$dir/requirements.txt" \
    --target "$dir" \
    --quiet \
    --upgrade
  echo "    Done."
done

# ── Terraform ─────────────────────────────────────────────────────────────────
cd "$SCRIPT_DIR/terraform"

echo ">>> terraform init"
terraform init -upgrade

echo ">>> terraform plan / apply"
terraform apply "$@"
