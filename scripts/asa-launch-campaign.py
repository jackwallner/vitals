#!/usr/bin/env python3
"""Launch a short Apple Search Ads test campaign for Total Calories.

Creates a US Search Results campaign with a daily budget, hard end date,
one ad group (Search Match + targeted keywords), and competitive CPT bids.

Auth (create once in Apple Ads → Account Settings → API):
  export ASA_CLIENT_ID="SEARCHADS...."
  export ASA_TEAM_ID="SEARCHADS...."
  export ASA_KEY_ID="...."
  export ASA_ORG_ID="12345678"
  export ASA_PRIVATE_KEY_PATH="$HOME/.appstoreconnect/searchads-private-key.pem"

Or put the same exports in ~/.searchads_env.sh (not committed).

Usage:
  python3 scripts/asa-launch-campaign.py --dry-run
  python3 scripts/asa-launch-campaign.py --commit
  python3 scripts/asa-launch-campaign.py --commit --days 2 --daily-budget 9
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

try:
    import jwt
except ImportError:
    sys.exit("error: pip install PyJWT cryptography")

API = "https://api.searchads.apple.com/api/v5"
TOKEN_URL = "https://appleid.apple.com/auth/oauth2/token"
ADAM_ID = 6761743504
APP_NAME = "Total Calories"
TZ = ZoneInfo("America/Los_Angeles")

# Winnable US keywords from Astro ASO strategy (avoid MFP-wall terms).
DEFAULT_KEYWORDS: list[tuple[str, str, float]] = [
    # (text, match_type, fallback_bid_usd) — fallback used if bid API unavailable
    ("daily burn", "EXACT", 3.25),
    ("tdee", "EXACT", 2.75),
    ("pacing", "EXACT", 2.00),
    ("daily calorie burn", "EXACT", 3.00),
    ("widget calories", "EXACT", 2.75),
    ("total burn", "EXACT", 2.50),
    ("tdee bmr", "EXACT", 2.00),
    ("apple watch calories", "EXACT", 4.00),
    ("metabolic", "EXACT", 2.00),
    ("bmr", "EXACT", 2.00),
]


def _load_env() -> None:
    if all(os.environ.get(k) for k in ("ASA_CLIENT_ID", "ASA_TEAM_ID", "ASA_KEY_ID", "ASA_ORG_ID", "ASA_PRIVATE_KEY_PATH")):
        return
    for src in (Path.home() / ".searchads_env.sh", Path.home() / ".baseball_credentials"):
        if not src.exists():
            continue
        for line in src.read_text().splitlines():
            line = line.strip()
            if line.startswith("export "):
                line = line[len("export ") :]
            if not line or line.startswith("#") or "=" not in line:
                continue
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))


def _require_env() -> tuple[str, str, str, str, Path]:
    _load_env()
    client_id = os.environ.get("ASA_CLIENT_ID")
    team_id = os.environ.get("ASA_TEAM_ID")
    key_id = os.environ.get("ASA_KEY_ID")
    org_id = os.environ.get("ASA_ORG_ID")
    key_path = os.environ.get("ASA_PRIVATE_KEY_PATH")
    missing = [n for n, v in [
        ("ASA_CLIENT_ID", client_id),
        ("ASA_TEAM_ID", team_id),
        ("ASA_KEY_ID", key_id),
        ("ASA_ORG_ID", org_id),
        ("ASA_PRIVATE_KEY_PATH", key_path),
    ] if not v]
    if missing:
        sys.exit(
            "error: missing Apple Search Ads credentials: "
            + ", ".join(missing)
            + "\nCreate API key at https://searchads.apple.com → Account Settings → API"
            + "\nThen save exports to ~/.searchads_env.sh"
        )
    path = Path(key_path).expanduser()
    if not path.exists():
        sys.exit(f"error: ASA private key not found: {path}")
    return client_id, team_id, key_id, org_id, path


def _client_secret(client_id: str, team_id: str, key_id: str, key_path: Path) -> str:
    iat = int(time.time())
    return jwt.encode(
        {
            "sub": client_id,
            "aud": "https://appleid.apple.com",
            "iat": iat,
            "exp": iat + 86400 * 180,
            "iss": team_id,
        },
        key_path.read_text(),
        algorithm="ES256",
        headers={"alg": "ES256", "kid": key_id},
    )


def _access_token(client_secret: str, client_id: str) -> str:
    body = urllib.parse.urlencode({
        "grant_type": "client_credentials",
        "client_id": client_id,
        "client_secret": client_secret,
        "scope": "searchadsorg",
    }).encode()
    req = urllib.request.Request(
        TOKEN_URL,
        data=body,
        method="POST",
        headers={
            "Host": "appleid.apple.com",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        data = json.loads(resp.read())
    token = data.get("access_token")
    if not token:
        sys.exit(f"error: token response missing access_token: {data}")
    return token


class ASA:
    def __init__(self, token: str, org_id: str) -> None:
        self.token = token
        self.org_id = org_id

    def request(self, method: str, path: str, body: dict | list | None = None) -> dict | list:
        url = f"{API}{path}"
        payload = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(
            url,
            data=payload,
            method=method,
            headers={
                "Authorization": f"Bearer {self.token}",
                "X-AP-Context": f"orgId={self.org_id}",
                "Content-Type": "application/json",
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=120) as resp:
                raw = resp.read()
                return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as e:
            detail = e.read().decode(errors="replace")
            sys.exit(f"error: {method} {path} → HTTP {e.code}\n{detail}")


def _asa_ts(dt: datetime) -> str:
    return dt.strftime("%Y-%m-%dT%H:%M:%S.000")


def _campaign_window(days: int) -> tuple[str, str]:
    start = datetime.now(TZ).replace(microsecond=0)
    # Hard stop exactly `days` after start (e.g. 2 days → ~48h, not “end of tomorrow”).
    end = start + timedelta(days=days)
    return _asa_ts(start), _asa_ts(end)


def _fetch_bid_recommendations(
    asa: ASA,
    campaign_id: int,
    ad_group_id: int,
    keywords: list[tuple[str, str, float]],
) -> dict[str, float]:
    """Return keyword -> competitive bid (USD). Falls back to seed bids."""
    bids = {text: fallback for text, _, fallback in keywords}
    candidates = [
        f"/campaigns/{campaign_id}/adgroups/{ad_group_id}/targetingkeywords/bidrecommendations",
        f"/campaigns/{campaign_id}/adgroups/{ad_group_id}/bidrecommendations",
    ]
    payload = {
        "keywords": [text for text, _, _ in keywords],
        "matchType": "EXACT",
        "countriesOrRegions": ["US"],
    }
    for path in candidates:
        try:
            url = f"{API}{path}"
            req = urllib.request.Request(
                url,
                data=json.dumps(payload).encode(),
                method="POST",
                headers={
                    "Authorization": f"Bearer {asa.token}",
                    "X-AP-Context": f"orgId={asa.org_id}",
                    "Content-Type": "application/json",
                },
            )
            with urllib.request.urlopen(req, timeout=120) as resp:
                data = json.loads(resp.read())
        except urllib.error.HTTPError:
            continue
        items = data if isinstance(data, list) else data.get("data", data.get("recommendations", []))
        if not isinstance(items, list):
            continue
        for item in items:
            text = item.get("text") or item.get("keyword")
            rec = item.get("bidRecommendation") or item.get("insights", {}).get("bidRecommendation") or item
            amount = None
            if isinstance(rec, dict):
                for key in ("suggestedBidAmount", "bidMax", "bidMin"):
                    slot = rec.get(key)
                    if isinstance(slot, dict) and slot.get("amount") not in (None, "null", ""):
                        amount = float(slot["amount"])
                        break
            if text and amount:
                # Use suggested/max for competitive placement; cap so $9/day isn't blown on one tap.
                bids[text] = min(max(amount, 1.50), 6.00)
        if bids:
            return bids
    return bids


def launch(
    *,
    commit: bool,
    days: int,
    daily_budget: float,
    campaign_name: str | None,
) -> None:
    start_time, end_time = _campaign_window(days)
    name = campaign_name or f"TC {days}d test {datetime.now(TZ).strftime('%Y-%m-%d')}"

    plan = {
        "app": APP_NAME,
        "adamId": ADAM_ID,
        "campaignName": name,
        "dailyBudgetUSD": daily_budget,
        "startTime": start_time,
        "endTime": end_time,
        "timezone": str(TZ),
        "placement": "APPSTORE_SEARCH_RESULTS",
        "country": "US",
        "keywords": [{"text": t, "match": m, "fallbackBid": b} for t, m, b in DEFAULT_KEYWORDS],
    }
    print(json.dumps(plan, indent=2))

    if not commit:
        print("\n(dry-run — pass --commit to create the campaign)")
        return

    client_id, team_id, key_id, org_id, key_path = _require_env()
    secret = _client_secret(client_id, team_id, key_id, key_path)
    token = _access_token(secret, client_id)
    asa = ASA(token, org_id)

    campaign_body = {
        "orgId": int(org_id),
        "name": name,
        "startTime": start_time,
        "endTime": end_time,
        "billingEvent": "TAPS",
        "dailyBudgetAmount": {"amount": f"{daily_budget:.2f}", "currency": "USD"},
        "adamId": ADAM_ID,
        "countriesOrRegions": ["US"],
        "status": "ENABLED",
        "supplySources": ["APPSTORE_SEARCH_RESULTS"],
        "adChannelType": "SEARCH",
        "biddingStrategy": "MANUAL_CPT",
    }
    camp_resp = asa.request("POST", "/campaigns", campaign_body)
    campaign_id = camp_resp["data"]["id"]
    print(f"created campaign id={campaign_id}")

    # Competitive default bid for Search Match (middle of keyword range).
    default_bid = 3.00
    ad_group_body = {
        "campaignId": campaign_id,
        "orgId": int(org_id),
        "name": f"{name} — core",
        "startTime": start_time,
        "endTime": end_time,
        "automatedKeywordsOptIn": True,
        "pricingModel": "CPC",
        "defaultBidAmount": {"amount": f"{default_bid:.2f}", "currency": "USD"},
        "status": "ENABLED",
    }
    ag_resp = asa.request("POST", f"/campaigns/{campaign_id}/adgroups", ad_group_body)
    ad_group_id = ag_resp["data"]["id"]
    print(f"created ad group id={ad_group_id} (Search Match on, default CPT ${default_bid:.2f})")

    bids = _fetch_bid_recommendations(asa, campaign_id, ad_group_id, DEFAULT_KEYWORDS)
    keyword_payload = [
        {
            "text": text,
            "matchType": match,
            "bidAmount": {"amount": f"{bids[text]:.2f}", "currency": "USD"},
        }
        for text, match, _ in DEFAULT_KEYWORDS
    ]
    kw_resp = asa.request(
        "POST",
        f"/campaigns/{campaign_id}/adgroups/{ad_group_id}/targetingkeywords/bulk",
        keyword_payload,
    )
    print(f"created {len(kw_resp)} targeting keywords")
    for item in kw_resp:
        print(f"  - {item['text']} ({item['matchType']}) @ ${item['bidAmount']['amount']}")

    print("\nCampaign is live (or will serve once Apple approves).")
    print(f"Hard stop: {end_time} {TZ}")
    print(f"Max ~${daily_budget:.2f}/day × {days} days ≈ ${daily_budget * days:.2f} total ceiling")
    print(f"Dashboard: https://searchads.apple.com/")


def list_orgs() -> None:
    client_id, team_id, key_id, org_id, key_path = _require_env()
    secret = _client_secret(client_id, team_id, key_id, key_path)
    token = _access_token(secret, client_id)
    asa = ASA(token, org_id)
    data = asa.request("GET", "/acls")
    print(json.dumps(data, indent=2))


def main() -> None:
    parser = argparse.ArgumentParser(description="Launch a short Apple Search Ads test for Total Calories")
    parser.add_argument("--commit", action="store_true", help="Actually create the campaign (default: dry-run)")
    parser.add_argument("--dry-run", action="store_true", help="Print plan only (default)")
    parser.add_argument("--list-orgs", action="store_true", help="Print ACL / org list (needs creds)")
    parser.add_argument("--days", type=int, default=2, help="Campaign length in calendar days (default: 2)")
    parser.add_argument("--daily-budget", type=float, default=9.0, help="Daily budget in USD (default: 9)")
    parser.add_argument("--name", help="Campaign name override")
    args = parser.parse_args()
    if args.list_orgs:
        list_orgs()
        return
    commit = args.commit and not args.dry_run
    if args.days < 1:
        sys.exit("error: --days must be >= 1")
    launch(commit=commit, days=args.days, daily_budget=args.daily_budget, campaign_name=args.name)


if __name__ == "__main__":
    main()
