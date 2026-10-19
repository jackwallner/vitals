import Foundation

/// A goal the daily notifications can talk about. Macros and Net Deficit are
/// deliberately absent: their numbers depend on food the user may log late.
enum NudgeMetric: String, Sendable, CaseIterable {
    case calories
    case steps
}

struct NudgeContent: Equatable, Sendable {
    let title: String
    let body: String
    let link: DeepLink
}

/// Pure copy and decision logic for the daily notifications (goal reached, and
/// the Vitals+ evening reminder with its streak saver). No HealthKit, no
/// notification center: `DailyNudgeService` feeds it numbers and posts what it
/// returns, so the rules are unit-testable.
enum DailyNudgePlanner {
    /// Walking pace used to turn a step shortfall into minutes. 100 steps a
    /// minute is the usual brisk-walk figure.
    static let stepsPerMinute = 100.0
    /// Above this the walk clause stops being encouraging and starts being a chore list.
    static let maxWalkMinutes = 120
    /// A streak this long is worth naming in the evening reminder.
    static let minStreakToSave = 2

    // MARK: Goal reached

    /// Goals met right now that haven't been announced today, calories first.
    static func newlyReached(
        calories: Double,
        steps: Int,
        calorieGoal: Double?,
        stepGoal: Int?,
        announced: Set<NudgeMetric>
    ) -> [NudgeMetric] {
        var reached: [NudgeMetric] = []
        if let goal = calorieGoal, goal > 0, calories >= goal, !announced.contains(.calories) {
            reached.append(.calories)
        }
        if let goal = stepGoal, goal > 0, steps >= goal, !announced.contains(.steps) {
            reached.append(.steps)
        }
        return reached
    }

    static func goalReached(
        _ reached: [NudgeMetric],
        calories: Double,
        steps: Int,
        calorieGoal: Double?,
        stepGoal: Int?
    ) -> NudgeContent? {
        let hitCalories = reached.contains(.calories)
        let hitSteps = reached.contains(.steps)
        if hitCalories && hitSteps {
            return NudgeContent(
                title: "Both goals reached",
                body: "\(formatCalories(calories)) cal burned and \(formatSteps(steps)) steps today.",
                link: .today
            )
        }
        if hitCalories, let goal = calorieGoal {
            return NudgeContent(
                title: "Calorie goal reached",
                body: "\(formatCalories(calories)) of \(formatCalories(goal)) cal burned today.",
                link: .metric(.calories)
            )
        }
        if hitSteps, let goal = stepGoal {
            return NudgeContent(
                title: "Step goal reached",
                body: "\(formatSteps(steps)) of \(formatSteps(goal)) steps today.",
                link: .metric(.steps)
            )
        }
        return nil
    }

    // MARK: Evening reminder

    /// Resting burn still to come before midnight at today's resting rate so far.
    /// The calorie goal counts resting energy, which keeps accruing while the
    /// user sleeps, so "to go" has to net it out or every evening reminder would
    /// overstate the gap by a few hundred calories.
    static func expectedRemainingResting(
        resting: Double,
        now: Date,
        calendar: Calendar = .current
    ) -> Double {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }
        let elapsed = now.timeIntervalSince(start)
        // Too little of the day has passed for the rate to mean anything.
        guard elapsed >= 3600, resting > 0 else { return 0 }
        let remaining = max(end.timeIntervalSince(now), 0)
        return resting / elapsed * remaining
    }

    /// Active calories still needed to land on the calorie goal by midnight, or
    /// nil when there's no goal or resting burn alone will get there.
    static func calorieShortfall(
        active: Double,
        resting: Double,
        goal: Double?,
        now: Date,
        calendar: Calendar = .current
    ) -> Double? {
        guard let goal, goal > 0 else { return nil }
        let projected = active + resting + expectedRemainingResting(resting: resting, now: now, calendar: calendar)
        let gap = goal - projected
        guard gap >= 10 else { return nil }
        return (gap / 10).rounded(.up) * 10
    }

    static func stepShortfall(steps: Int, goal: Int?) -> Int? {
        guard let goal, goal > 0, steps < goal else { return nil }
        let gap = goal - steps
        return Int((Double(gap) / 100).rounded(.up)) * 100
    }

    /// Minutes of walking that cover `steps`, rounded up to 5. nil when it's
    /// too long to suggest.
    static func walkMinutes(forSteps steps: Int) -> Int? {
        let raw = Int((Double(steps) / stepsPerMinute).rounded(.up))
        let rounded = max(5, Int((Double(raw) / 5).rounded(.up)) * 5)
        return rounded <= maxWalkMinutes ? rounded : nil
    }

    /// The evening reminder, or nil when every goal is met or on track to be.
    /// A live streak on a goal that's still open leads the title: losing a
    /// streak is the strongest reason to get up at 7pm.
    static func evening(
        active: Double,
        resting: Double,
        steps: Int,
        calorieGoal: Double?,
        stepGoal: Int?,
        calorieStreak: Int,
        stepStreak: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> NudgeContent? {
        let calGap = calorieShortfall(active: active, resting: resting, goal: calorieGoal, now: now, calendar: calendar)
        let stepGap = stepShortfall(steps: steps, goal: stepGoal)
        guard calGap != nil || stepGap != nil else { return nil }

        let calText = calGap.map { "about \(formatCalories($0)) active cal" }
        let stepText = stepGap.map { "\(formatSteps($0)) steps" }
        let walk = stepGap.flatMap(walkMinutes(forSteps:))

        let savedStreak = streakToSave(
            calorieStreak: calGap == nil ? 0 : calorieStreak,
            stepStreak: stepGap == nil ? 0 : stepStreak
        )
        if case let (metric, days)? = savedStreak {
            let noun = metric == .steps ? "step" : "calorie"
            let gaps = [stepText, calText].compactMap { $0 }.joined(separator: " and ")
            var body = "\(capitalizedFirst(gaps)) to go today"
            if let walk, metric == .steps { body += ", about a \(walk) min walk" }
            return NudgeContent(
                title: "Keep your \(days)-day \(noun) streak",
                body: body + ".",
                link: .today
            )
        }

        switch (calText, stepText) {
        case let (cal?, steps?):
            return NudgeContent(
                title: "Today's goals are still open",
                body: "\(steps) and \(cal) to go.",
                link: .today
            )
        case let (nil, steps?):
            let body = walk.map { "About a \($0) min walk closes out your step goal." }
                ?? "Still time to close out your step goal."
            return NudgeContent(title: "\(capitalizedFirst(steps)) to go", body: body, link: .today)
        case let (cal?, nil):
            return NudgeContent(
                title: "\(capitalizedFirst(cal)) to go",
                body: "A little more movement closes out your calorie goal.",
                link: .today
            )
        case (nil, nil):
            return nil
        }
    }

    /// The longer live streak among goals still open; steps win a tie because
    /// a walk is the easier thing to do about it.
    private static func streakToSave(calorieStreak: Int, stepStreak: Int) -> (NudgeMetric, Int)? {
        let best = max(calorieStreak, stepStreak)
        guard best >= minStreakToSave else { return nil }
        return stepStreak >= calorieStreak ? (.steps, stepStreak) : (.calories, calorieStreak)
    }

    // MARK: Formatting

    static func formatCalories(_ value: Double) -> String {
        Int(value.rounded()).formatted(.number)
    }

    static func formatSteps(_ value: Int) -> String {
        value.formatted(.number)
    }

    private static func capitalizedFirst(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}
