# Apple Review 3.1.2(c) — Build 71 Metadata Fix

**TL;DR:** No binary resubmit needed. Update App Description + reply to App Review. Apple already said this is bug-fix-eligible.

---

## 1. App Description — append this block

App Store Connect → Apps → Total Calories - Daily Tracker → version 1.5.0 → **App Information** (or the version's **Description** field). Append to the bottom:

```
Subscription Details
Vitals+ is available as an auto-renewing subscription (Monthly $1.99 / Yearly $14.99 with a 7-day free trial) or a one-time Lifetime purchase ($29.99). Payment is charged to your Apple ID at confirmation. Subscriptions auto-renew unless cancelled at least 24 hours before the end of the period. Manage or cancel anytime in Settings → Apple ID → Subscriptions.

Privacy Policy: https://jackwallner.github.io/vitals/privacy-policy.html
Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

The "Terms of Use (EULA): https://..." line is the specific thing Apple is asking for. Save.

**Optional:** App Information → **License Agreement** → confirm "Standard Apple EULA" is selected (matches the URL above).

---

## 2. Reply to App Review

Paste in the rejection thread in App Store Connect:

```
Hi App Review team,

Thanks for the feedback. 1.5.0 (build 71) is a bug-fix update and we'd like to have it approved at this time per your message.

We've updated the App Description to include a functional link to the standard Apple Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/ — alongside the existing Privacy Policy link.

The paywall inside the app already presents Title, Length, Price, Privacy Policy, and Terms of Use prior to purchase. Functional Terms of Use link in-app: see "Terms of Use" at the bottom of the Vitals+ purchase screen (refer to your review screenshot at 8:46 on iPhone 17 Pro Max).

For future submissions, we've added this information to App Review Information → Notes as well.

Please let us know if anything else is needed.

Thanks,
Jack
```

Attach the paywall screenshot (the one showing Privacy Policy · Terms of Use at the bottom).

---

## 3. App Review Information → Notes — append

Same version page → **App Review Information** → **Notes**:

```
Vitals+ subscription details and EULA link are included in the App Description. The in-app paywall displays subscription title, length, price, Privacy Policy, and Terms of Use prior to purchase, per Guideline 3.1.2.
```

Prevents this round-trip on future submissions.

---

## Checklist

- [ ] App Description updated with Subscription Details + EULA link
- [ ] License Agreement is set to Standard Apple EULA
- [ ] Reply sent in App Review thread with paywall screenshot attached
- [ ] App Review Information Notes updated
- [ ] (Queued for next build) Switch in-app paywall to RevenueCatUI hosted paywall for A/B testing
