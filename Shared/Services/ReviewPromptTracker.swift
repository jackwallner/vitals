import Foundation

extension Notification.Name {
    /// Posted after a good moment (a daily goal hit); the host may call requestReview() after a short delay.
    static let vitalsPositiveMomentForReview = Notification.Name("com.jackwallner.vitals.positiveMomentForReview")
}

/// What the user did about a review. Only opening the review page ends the
/// passive asks: someone who sent feedback can still rate.
enum ReviewPromptOutcome: String, Sendable {
    /// Opened the App Store write-review page from Settings.
    case openedWriteReview
    /// Sent feedback. Recorded for the cooldown; it no longer stops asks.
    case submittedFeedback
}

/// The only results that ask for a rating: a daily goal the user just hit, or
/// a goal-streak milestone they just reached. Launches, tab or view appearances,
/// open counts, reports, recaps, widgets and subscriber tenure never ask.
enum ReviewMoment {
    /// Today's calorie or step goal was crossed.
    static func dailyGoalHit(crossedCalories: Bool, crossedSteps: Bool) -> Bool {
        crossedCalories || crossedSteps
    }

    /// A streak tier is a good result; a month review is a summary, not a win.
    static func isGood(_ event: MilestoneEvent) -> Bool {
        if case .goalStreak = event { return true }
        return false
    }
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

    /// Ask early. Most installs are gone within a week, and a rating from
    /// someone who hit one goal beats no rating at all. The only tenure gate is
    /// "not the first session": a second cold start.
    static let minimumLaunchCount = 2
    /// Days between rating asks. Apple's `requestReview()` often shows nothing
    /// (three a year per device), so this paces our calls, not the user's answers.
    static let cooldownDays = 30

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

    private static var launchCountedThisProcess = false

    /// Counts a launch once per process, at its first foreground moment. The app
    /// object is also built when iOS relaunches it in the background (Health
    /// delivery, refresh), and those runs are not a time the customer opened it.
    @discardableResult
    static func recordForegroundLaunchOnce(now: Date = .now) -> Bool {
        guard !launchCountedThisProcess else { return false }
        launchCountedThisProcess = true
        recordAppLaunch(now: now)
        ConversionDiagnostics.recordAppOpen()
        return true
    }

    /// Test hook: lets a test act as a fresh process.
    static func resetLaunchCountedForTesting() { launchCountedThisProcess = false }

    /// Adds one launch. Call it through `recordForegroundLaunchOnce`.
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

    /// A milestone moment that only ever counts once, keyed by what caused it
    /// (`milestone_streak_30`). Returns whether it fired.
    @discardableResult
    static func recordOneShotPositiveMoment(key: String) -> Bool {
        let storageKey = "reviewPrompt.oneShot.\(key)"
        guard !defaults.bool(forKey: storageKey) else { return false }
        defaults.set(true, forKey: storageKey)
        recordPositiveMoment()
        return true
    }

    static func consumePendingPositiveMoment() {
        hasPendingPositiveMoment = false
    }

    static func passivePromptAllowed(now: Date = .now) -> Bool {
        guard outcome != .openedWriteReview else { return false }
        guard let last = lastShownDate else { return true }
        let cooldown = TimeInterval(cooldownDays) * 86_400
        return now.timeIntervalSince(last) >= cooldown
    }

    /// Base eligibility for the rating ask. The pending positive moment is
    /// checked by the caller; any one moment is enough.
    static func canRequestReview(hasCompletedSetup: Bool, now: Date = .now) -> Bool {
        guard !ScreenshotConfig.isEnabled else { return false }
        guard hasCompletedSetup else { return false }
        guard passivePromptAllowed(now: now) else { return false }
        return appLaunchCount >= minimumLaunchCount
    }

    /// Passive prompt: eligibility plus a recent positive moment.
    static func shouldShowAfterPositiveMoment(
        hasCompletedSetup: Bool,
        now: Date = .now
    ) -> Bool {
        guard hasPendingPositiveMoment else { return false }
        return canRequestReview(hasCompletedSetup: hasCompletedSetup, now: now)
    }

    static func markShown(now: Date = .now) {
        lastShownDate = now
        consumePendingPositiveMoment()
    }

    static func markOpenedWriteReview() {
        outcome = .openedWriteReview
        markShown()
    }

    /// Never overwrites `.openedWriteReview`: feedback sent after the review
    /// page must not reopen the asks that page ended.
    static func markFeedbackSubmitted() {
        if outcome != .openedWriteReview {
            outcome = .submittedFeedback
        }
        markShown()
    }
}
