import SwiftUI
import UIKit

/// Routes the Settings "Send Feedback" row to the host that owns the sheets.
@MainActor
final class ReviewPromptCoordinator: ObservableObject {
    static let shared = ReviewPromptCoordinator()

    enum Presentation {
        case feedbackOnly
    }

    @Published var pendingPresentation: Presentation?

    private init() {}

    func requestFeedback() {
        pendingPresentation = .feedbackOnly
    }

    func clear() {
        pendingPresentation = nil
    }
}

/// Returned when the sheet closes.
enum ReviewPromptDismissOutcome: Sendable {
    case notNow
    case feedbackSubmitted
}

/// Private, account-free feedback. The rating ask is separate: the host calls
/// `requestReview()` directly at a positive moment, with no question in front
/// of it (App Review 5.6.1), so this sheet never mentions the App Store.
struct ReviewPromptSheet: View {
    /// The trial note's "tell us what to fix", asked when its trial stops renewing.
    var asksWhatToFix = false
    let onFinish: (ReviewPromptDismissOutcome) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var feedbackText = ""
    @FocusState private var feedbackFocused: Bool

    var body: some View {
        NavigationStack {
            feedbackContent
                .navigationTitle("Help us improve")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Not now") { finish(.notNow) }
                    }
                }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var feedbackContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            Group {
                if asksWhatToFix {
                    Text("Your trial won't renew. What should we fix?")
                } else {
                    Text("What would make Total Calories work better for you?")
                }
            }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $feedbackText)
                .font(.system(.body, design: .rounded))
                .frame(minHeight: 140, maxHeight: 220)
                .padding(10)
                .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 12))
                .focused($feedbackFocused)

            Text("Opens your mail app with a draft to the developer. No analytics, just your words.")
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textSecondary)

            Button {
                sendFeedback()
            } label: {
                Text("Send feedback")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.caloriesGradient, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(trimmedFeedback.isEmpty)
            .opacity(trimmedFeedback.isEmpty ? 0.5 : 1)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .onAppear { feedbackFocused = true }
    }

    private var trimmedFeedback: String {
        feedbackText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func sendFeedback() {
        guard !trimmedFeedback.isEmpty, let url = Self.feedbackMailURL(body: trimmedFeedback) else { return }
        ReviewPromptTracker.markFeedbackSubmitted()
        UIApplication.shared.open(url)
        finish(.feedbackSubmitted)
    }

    private func finish(_ outcome: ReviewPromptDismissOutcome) {
        onFinish(outcome)
        dismiss()
    }

    /// Pre-filled mailto for private, account-free feedback.
    static func feedbackMailURL(body: String) -> URL? {
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = "jackwallner+tc@gmail.com"
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Total Calories feedback"),
            URLQueryItem(name: "body", value: body),
        ]
        return components.url
    }
}
