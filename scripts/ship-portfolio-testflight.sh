#!/usr/bin/env bash
# Upload TestFlight builds for all portfolio apps (sequential). Does NOT submit for review.
set -euo pipefail

LOG="/tmp/portfolio-testflight.log"
APPS=(vitals posture bond fitness-streaks sober simpleglp sports baseball headaches nicfree)

exec > >(tee -a "$LOG") 2>&1

echo "=== Portfolio TestFlight upload started $(date) ==="

if [[ -f "$HOME/.baseball_credentials" ]]; then
  # shellcheck disable=SC1091
  source "$HOME/.baseball_credentials"
fi

for app in "${APPS[@]}"; do
  dir="$HOME/$app"
  script="$dir/scripts/testflight.sh"
  echo ""
  echo "============================================================"
  echo ">>> $app $(date)"
  echo "============================================================"
  if [[ ! -x "$script" ]]; then
    chmod +x "$script" 2>/dev/null || true
  fi
  if [[ ! -f "$script" ]]; then
    echo "SKIP: no testflight.sh"
    continue
  fi
  if (cd "$dir" && bash "$script"); then
    echo "OK: $app"
  else
    echo "FAILED: $app (exit $?)"
  fi
done

echo ""
echo "=== Portfolio TestFlight upload finished $(date) ==="
echo "Log: $LOG"
