#!/usr/bin/env bash
set -euo pipefail

if [ "${SEED_ON_INIT:-false}" != "true" ]; then
  echo "Skipping seed. Set SEED_ON_INIT=true before first database initialization to seed automatically."
  exit 0
fi

echo "Seeding database during first container initialization."

bash /seed/seed.sh
