# Localization ASO — Total Calories

**Uploaded:** 2026-05-26 — draft **1.5.3** (now **IN_REVIEW** — metadata locked until you reject or it ships).

**True native locales (2026-05-26):** `kn-IN`, `ml-IN`, `ta-IN`, `te-IN`, `bn-BD`, `gu-IN`, `mr-IN`, `or-IN`, `pa-IN`, `ur-PK`, `sl-SI` — source: `scripts/native_locale_content/*.json`, applied via `scripts/apply-native-locales.py`.

**Blocked upload:** Apple will not edit metadata or create **1.5.4** while **1.5.3** is `IN_REVIEW`. To push native copy to ASC:

1. App Store Connect → version **1.5.3** → **Remove from Review** (Developer Reject)
2. Then run:
   ```bash
   eval "$(python3 scripts/asc-ensure-draft-version.py | grep '^export ')"
   SKIP_SCREENSHOTS=true ./scripts/upload-appstore-metadata.sh
   ```

## Backups

| Snapshot | Path |
|----------|------|
| ASC pull (before edits) | `fastlane/metadata.bak.20260525-081116/` |
| Pre-upload (optimized copy) | `fastlane/metadata.bak.pre-upload-20260525-190321/` |

## Restore

```bash
# Restore from pre-upload snapshot
./scripts/restore-appstore-metadata.sh fastlane/metadata.bak.pre-upload-20260525-190321

# Or from original ASC pull
./scripts/restore-appstore-metadata.sh fastlane/metadata.bak.20260525-081116
```

## Re-upload after edits

```bash
eval "$(python3 scripts/asc-ensure-draft-version.py | grep '^export ')"
./scripts/asc-finish-missed.sh
# metadata only (no screenshots):
# SKIP_SCREENSHOTS=true ./scripts/upload-appstore-metadata.sh
```

## Playbook

See [`astro-global-aso-go-2026.md`](astro-global-aso-go-2026.md) — keywords must **not repeat** tokens already in `name.txt` or `subtitle.txt` (deduped by `scripts/aso-apply-locale-optimizations.py`).
