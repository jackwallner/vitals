#!/bin/bash
# Re-sync Astro stores that still have gaps (added < missing in _summary.json).
set -euo pipefail
cd "$(dirname "$0")/.."
SUMMARY="scripts/astro-keywords-by-store/_summary.json"
[[ -f "$SUMMARY" ]] || { echo "Run astro-sync-all-stores.sh first"; exit 1; }
STORES=$(python3 - <<'PY'
import json
s = json.load(open("scripts/astro-keywords-by-store/_summary.json"))
for code, info in sorted(s.get("stores", {}).items()):
    if info.get("skipped"):
        continue
    gap = info.get("gap", 0)
    missing = info.get("missing", 0)
    added = info.get("added", 0)
    if gap > 0 or (missing > 0 and added == 0):
        print(code)
PY
)
if [[ -z "$STORES" ]]; then
  echo "No stores with gaps."
  exit 0
fi
echo "Retrying: $STORES"
for code in $STORES; do
  echo "==> retry $code"
  PYTHONUNBUFFERED=1 python3 scripts/astro-sync-all-stores.py --store "$code"
  sleep 3
done
