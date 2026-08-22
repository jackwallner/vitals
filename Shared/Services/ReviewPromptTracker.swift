import Foundation

extension Notification.Name {
    /// Posted when the user hits a daily goal — host may present the enjoyment funnel after a short delay.
    static let vitalsPositiveMomentForReview = Notification.Name("com.jackwallner.vitals.positiveMomentForReview")
}

/// How the user last resolved the in-app review / feedback prompt.
enum ReviewPromptOutcome: String, Sendable {
    /// Opened the App Store write-review page (explicit CTA).
    case openedWriteReview
    /// Opened the feedback mail composer with a message.
    case submittedFeedback
}

/// Persists launch counts, positive moments, and review-prompt eligibility in the app group.
@MainActor
enum ReviewPromptTracker {
    private static let defaults = UserDefaults(suiteName: vitalsAppGroupID) ?? .standard

    private static let launchCountKey = "reviewPrompt.appLaunchCount"
    private static let firstOpenKey = "reviewPrompt.firstAppOpenDate"
    private static let lastShownKey = "reviewPrompt.lastShownDate"
    private static let outcomeKey = "reviewPrompt.outcome"
    private static let positiveMomentCountKey = "reviewPrompt.positiveMomentCount"
    private static let pendingPositiveMomentKey = "reviewPrompt.pendingPositiveMoment"
    private static let softDeferKey = "reviewPrompt.softDefer"
    private static let trackedDayCountKey = "reviewPrompt.trackedDayCount"
    private static let lastTrackedDayKey = "reviewPrompt.lastTrackedDay"
    private static let habitMomentFiredKey = "reviewPrompt.habitMomentFired"
    private static let proSinceKey = "reviewPrompt.proSince"
    private static let subscriberMomentFiredKey = "reviewPrompt.subscriberMomentFired"

    /// Minimum cold starts before passive prompts are considered.
    static let minimumLaunchCount = 3
    /// Minimum days since first open.
    static let minimumDaysSinceFirstOpen = 3
    /// Minimum *cumulative* positive moments (goal hits) before we surface the
    /// enjoyment funnel. Two good days is enough signal they like the app.
    static let minimumPositiveMoments = 2
    /// Distinct days the app has been opened before the habit itself counts as a
    /// positive moment. A goal hit is the outcome; this is the behaviour, and it
    /// catches everyone using the app happily without ever clearing a goal.
    static let minimumTrackedDays = 7
    /// Days a paying subscriber must have kept Vitals+ before that counts as a
    /// positive moment. They paid, stayed, and never cancelled — the best-disposed
    /// group the app has, and previously treated like a first-day stranger.
    static let subscriberMomentDays = 30
    /// Days before "Not now" can surface the enjoyment prompt again. At this app's
    /// volume 120 days was effectively one ask per user, forever.
    static let cooldownDays = 60
    /// Shorter cooldown after "Maybe later" on the review pitch — Apple's
    /// `requestReview()` often shows nothing, so a 120-day jail was burning asks.
    static let softDeferCooldownDays = 30

    static var appLaunchCount: Int {
        get { max(defaults.integer(forKey: launchCountKey), 0) }
        set { defaults.set(newValue, forKey: launchCountKey) }
    }

    static var firstAppOpenDate: Date? {
        get { defaults.object(forKey: firstOpenKey) as? Date }
        set {
            if let date = newValue {
                defaults.set(date, forKey: firstOpenKey)
            } else {
                defaults.removeObject(forKey: firstOpenKey)
            }
        }
    }

    static var lastShownDate: Date? {
        get { defaults.object(forKey: lastShownKey) as? Date }
        set {
            if let date = newValue {
                defaults.set(date, forKey: lastShownKey)
            } else {
                defaults.removeObject(forKey: lastShownKey)
            }
        }
    }

    static var outcome: ReviewPromptOutcome? {
        get {
            guard let raw = defaults.string(forKey: outcomeKey) else { return nil }
            return ReviewPromptOutcome(rawValue: raw)
        }
        set {
            if let value = newValue {
                defaults.set(value.rawValue, forKey: outcomeKey)
            } else {
                defaults.removeObject(forKey: outcomeKey)
            }
        }
    }

    static var positiveMomentCount: Int {
        get { max(defaults.integer(forKey: positiveMomentCountKey), 0) }
        set { defaults.set(newValue, forKey: positiveMomentCountKey) }
    }

    /// Set when a positive moment fires; cleared when a passive prompt is shown or consumed.
    static var hasPendingPositiveMoment: Bool {
        get { defaults.bool(forKey: pendingPositiveMomentKey) }
        set { defaults.set(newValue, forKey: pendingPositiveMomentKey) }
    }

    /// Call once per process launch (e.g. from `VitalsApp.init`).
    static func recordAppLaunch(now: Date = .now) {
        if firstAppOpenDate == nil {
            firstAppOpenDate = now
        }
        appLaunchCount += 1
    }

    /// Call after a satisfaction moment (e.g. daily goal reached).
    static func recordPositiveMoment() {
        positiveMomentCount += 1
        hasPendingPositiveMoment = true
    }

    /// Distinct calendar days the app has been opened.
    static var trackedDayCount: Int {
        get { max(defaults.integer(forKey: trackedDayCountKey), 0) }
        set { defaults.set(newValue, forKey: trackedDayCountKey) }
    }

    /// Records today against the tracked-day streak and reports whether this is
    /// the launch that crossed `minimumTrackedDays`. Fires at most once ever.
    static func recordTrackedDay(now: Date = .now) -> Bool {
        let today = Calendar.current.startOfDay(for: now)
        if let last = defaults.object(forKey: lastTrackedDayKey) as? Date,
           Calendar.current.isDate(last, inSameDayAs: today) {
            return false
        }
        defaults.set(today, forKey: lastTrackedDayKey)
        trackedDayCount += 1
        guard trackedDayCount >= minimumTrackedDays,
              !defaults.bool(forKey: habitMomentFiredKey) else { return false }
        defaults.set(true, forKey: habitMomentFiredKey)
        recordPositiveMoment()
        return true
    }

    /// Stamps when Vitals+ first turned on and reports whether the subscriber has
    /// now held it for `subscriberMomentDays`. Fires at most once ever, and only
    /// while they still have it — a lapsed subscriber is not a happy moment.
    static func recordProStatus(isPro: Bool, now: Date = .now) -> Bool {
        guard isPro else { return false }
        guard let since = defaults.object(forKey: proSinceKey) as? Date else {
            defaults.set(now, forKey: proSinceKey)
            return false
        }
        let elapsed = now.timeIntervalSince(since)
        guard elapsed >= TimeInterval(subscriberMomentDays) * 86_400,
              !defaults.bool(forKey: subscriberMomentFiredKey) else { return false }
        defaults.set(true, forKey: subscriberMomentFiredKey)
        recordPositiveMoment()
        return true
    }

    /// A positive moment that must only ever count once, keyed by what caused it
    /// (`streak_30`, `report_exported`, …). Returns whether it fired.
    ///
    /// The repeatable moment is hitting a daily goal. Everything else here is a
    /// milestone — counting it twice would inflate `positiveMomentCount` past
    /// the threshold on behaviour the user only did once.
    @discardableResult
    static func recordOneShotPositiveMoment(key: String) -> Bool {
        let storageKey = "reviewPrompt.oneShot.\(key)"
        guard !defaults.bool(forKey: storageKey) else { return false }
        defaults.set(true, forKey: storageKey)
        recordPositiveMoment()
        return true
    }

    /// One-shot moment recorded from somewhere that can't present the funnel
    /// itself (a report generated on History, say). Posts so whichever host owns
    /// the tabs can decide; if it can't ask right now the moment stays pending
    /// and is picked up on the next visit to Today.
    static func recordOneShotPositiveMomentAndNotify(key: String) {
        guard recordOneShotPositiveMoment(key: key) else { return }
        NotificationCenter.default.post(name: .vitalsPositiveMomentForReview, object: nil)
    }

    static func consumePendingPositiveMoment() {
        hasPendingPositiveMoment = false
    }

    static func passivePromptAllowed(now: Date = .now) -> Bool {
        guard outcome == nil else { return false }
        guard let last = lastShownDate else { return true }
        let days = defaults.bool(forKey: softDeferKey) ? softDeferCooldownDays : cooldownDays
        let cooldown = TimeInterval(days) * 86_400
        return now.timeIntervalSince(last) >= cooldown
    }

    /// Base eligibility for the enjoyment funnel (passive or Settings).
    static func canPresentEnjoymentPrompt(
        hasCompletedSetup: Bool,
        now: Date = .now
    ) -> Bool {
        guard !ScreenshotConfig.isEnabled else { return false }
        guard hasCompletedSetup else { return false }
        guard passivePromptAllowed(now: now) else { return false }
        guard appLaunchCount >= minimumLaunchCount else { return false }
        guard positiveMomentCount >= minimumPositiveMoments else { return false }
        guard let first = firstAppOpenDate else { return false }
        let minInterval = TimeInterval(minimumDaysSinceFirstOpen) * 86_400
        guard now.timeIntervalSince(first) >= minInterval else { return false }
        return true
    }

    /// Passive prompt: eligibility plus a recent positive moment.
    static func shouldShowAfterPositiveMoment(
        hasCompletedSetup: Bool,
        now: Date = .now
    ) -> Bool {
        guard hasPendingPositiveMoment else { return false }
        return canPresentEnjoymentPrompt(hasCompletedSetup: hasCompletedSetup, now: now)
    }

    static func markShown(now: Date = .now) {
        lastShownDate = now
        defaults.set(false, forKey: softDeferKey)
        consumePendingPositiveMoment()
    }

    /// True after "Maybe later" until the next hard `markShown` / outcome.
    /// Hosts must not call `markShown()` on sheet dismiss when this is true —
    /// that would clear the soft-defer flag and apply the 120-day jail instead.
    static var isSoftDeferred: Bool {
        defaults.bool(forKey: softDeferKey)
    }

    /// User said Yes then "Maybe later" — we fire `requestReview()` which Apple
    /// often silently no-ops. Use a short cooldown so we can ask again instead
    /// of jailing them for 120 days.
    static func markSoftDeferred(now: Date = .now) {
        lastShownDate = now
        defaults.set(true, forKey: softDeferKey)
        consumePendingPositiveMoment()
    }

    static func markOpenedWriteReview() {
        outcome = .openedWriteReview
        markShown()
    }

    static func markFeedbackSubmitted() {
        outcome = .submittedFeedback
        markShown()
    }
}
