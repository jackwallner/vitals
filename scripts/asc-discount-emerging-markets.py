#!/usr/bin/env python3
"""Apply the three-tier emerging-market discount plan to Vitals+ subscriptions."""
import sys, json, time, urllib.parse
sys.path.insert(0, "scripts")
from asc_lib import load_credentials, bearer_token, ASCClient

# Tier assignments. Each value is the target USD-equivalent ceiling.
TIERS = {
    # Severe-gap markets — target ~$4.99 yearly / ~$0.69 monthly
    "IND": (4.99, 0.69),  # India
    "PAK": (4.99, 0.69),  # Pakistan
    "BGD": (4.99, 0.69),  # Bangladesh
    "IDN": (4.99, 0.69),  # Indonesia
    "VNM": (4.99, 0.69),  # Vietnam
    "PHL": (4.99, 0.69),  # Philippines
    "EGY": (4.99, 0.69),  # Egypt
    "NGA": (4.99, 0.69),  # Nigeria
    # Moderate-gap markets — target ~$7.99 yearly / ~$0.99 monthly
    "TUR": (7.99, 0.99),  # Turkey
    "BRA": (7.99, 0.99),  # Brazil
    "MEX": (7.99, 0.99),  # Mexico
    "COL": (7.99, 0.99),  # Colombia
    "CHL": (7.99, 0.99),  # Chile
    "THA": (7.99, 0.99),  # Thailand
    "MYS": (7.99, 0.99),  # Malaysia
    "POL": (7.99, 0.99),  # Poland
    "HUN": (7.99, 0.99),  # Hungary
    "ROU": (7.99, 0.99),  # Romania
    "ZAF": (7.99, 0.99),  # South Africa
    "RUS": (7.99, 0.99),  # Russia
    # Light-gap markets — target ~$11.99 yearly / ~$1.49 monthly
    "SAU": (11.99, 1.49), # Saudi Arabia
    "ARE": (11.99, 1.49), # UAE
    "CZE": (11.99, 1.49), # Czech Republic
    "CHN": (11.99, 1.49), # China
}

# FX rates (USD per 1 unit of local currency) — needed to estimate USD-equivalent
# of each available price point. Approximate, but only used for ranking.
FX = {
    "INR": 0.012,  "PKR": 0.0036, "BDT": 0.0082, "IDR": 0.000062, "VND": 0.0000395,
    "PHP": 0.0173, "EGP": 0.020,  "NGN": 0.00065,
    "TRY": 0.029,  "BRL": 0.20,   "MXN": 0.049,  "COP": 0.00024,  "CLP": 0.0011,
    "THB": 0.029,  "MYR": 0.22,   "PLN": 0.25,   "HUF": 0.0028,   "RON": 0.22,
    "ZAR": 0.055,  "RUB": 0.011,
    "SAR": 0.27,   "AED": 0.27,   "CZK": 0.044,  "CNY": 0.14,
    "USD": 1.0,
}

# Apple price-point endpoint doesn't return currency code directly. We infer it
# by territory ISO-3 → currency mapping.
TERRITORY_CURRENCY = {
    "IND":"INR","PAK":"PKR","BGD":"BDT","IDN":"IDR","VNM":"VND","PHL":"PHP",
    "EGY":"EGP","NGA":"NGN","TUR":"TRY","BRA":"BRL","MEX":"MXN","COL":"COP",
    "CHL":"CLP","THA":"THB","MYS":"MYR","POL":"PLN","HUN":"HUF","ROU":"RON",
    "ZAF":"ZAR","RUS":"RUB","SAU":"SAR","ARE":"AED","CZE":"CZK","CHN":"CNY",
}

SUBS = [
    ("6767107405", "Yearly",  0),  # idx 0 in TIERS tuple
    ("6767107539", "Monthly", 1),  # idx 1 in TIERS tuple
]


def pick_price_point(client, sub_id, terr, target_usd):
    """Return (price_point_id, customer_price, usd_eq) for the highest available
    price point whose USD-equivalent is ≤ target_usd."""
    r = client.get(f"/subscriptions/{sub_id}/pricePoints?filter[territory]={terr}&limit=200")
    pts = []
    ccy = TERRITORY_CURRENCY.get(terr, "USD")
    fx = FX.get(ccy, 1.0)
    for p in r["data"]:
        cp = float(p["attributes"]["customerPrice"])
        usd_eq = cp * fx
        pts.append((usd_eq, cp, p["id"]))
    pts.sort()
    # Pick the highest price ≤ target; if all are above target, pick the lowest.
    eligible = [x for x in pts if x[0] <= target_usd]
    pick = eligible[-1] if eligible else pts[0]
    return pick[2], pick[1], pick[0]


from datetime import date, timedelta

# Apple requires the change to be scheduled at least one full day out for
# approved subscriptions. Use 2 days out to be safe across TZ rollover.
SCHEDULED_START = (date.today() + timedelta(days=2)).isoformat()


def create_price(client, sub_id, terr_id, pp_id):
    """Schedule a price change on an approved subscription. Existing subscribers
    keep their current price (preserveCurrentPrice=True) — only new sign-ups
    after `SCHEDULED_START` see the new price."""
    body = {
        "data": {
            "type": "subscriptionPrices",
            "attributes": {"preserveCurrentPrice": True, "startDate": SCHEDULED_START},
            "relationships": {
                "subscription": {"data": {"type": "subscriptions", "id": sub_id}},
                "territory": {"data": {"type": "territories", "id": terr_id}},
                "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": pp_id}},
            },
        }
    }
    return client.post("/subscriptionPrices", body)


def main():
    key_id, issuer_id, key_path = load_credentials()
    client = ASCClient(bearer_token(key_id, issuer_id, key_path))

    summary = []
    for sub_id, label, idx in SUBS:
        print(f"\n=== {label} ({sub_id}) ===")
        for terr, targets in TIERS.items():
            target_usd = targets[idx]
            try:
                pp_id, cp, usd_eq = pick_price_point(client, sub_id, terr, target_usd)
            except Exception as e:
                print(f"  {terr}: pp-fetch fail: {e}")
                continue
            try:
                create_price(client, sub_id, terr, pp_id)
                print(f"  {terr}: → {cp} ({TERRITORY_CURRENCY.get(terr)}) ≈ ${usd_eq:.2f} (target ≤ ${target_usd})")
                summary.append((label, terr, cp, usd_eq))
            except Exception as e:
                msg = str(e)[:160]
                print(f"  {terr}: post fail: {msg}")
            time.sleep(0.20)

    print(f"\nApplied {len(summary)} price changes.")


if __name__ == "__main__":
    main()
