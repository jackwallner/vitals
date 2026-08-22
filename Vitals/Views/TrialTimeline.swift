import SwiftUI

/// Blinkist-style three-step trial. Middle step is the last day to cancel
/// (Apple's 24-hour rule), not a claim that Apple will send a reminder.
struct TrialTimeline: View {
    let trialDays: Int
    let priceLabel: String?

    private var copy: VitalsConversionCopy.TrialTimelineCopy {
        .make(trialDays: trialDays, priceLabel: priceLabel)
    }

    var body: some View {
        let copy = self.copy
        VStack(alignment: .leading, spacing: 0) {
            Text("How your free trial works")
                .font(.system(.subheadline, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 12)

            step(
                icon: "lock.open.fill",
                tint: Theme.stepsPrimary,
                title: copy.todayTitle,
                detail: copy.todayDetail,
                isLast: false
            )
            step(
                icon: "hand.raised.fill",
                tint: Theme.caloriesPrimary,
                title: copy.cancelTitle,
                detail: copy.cancelDetail,
                isLast: false
            )
            step(
                icon: "checkmark.seal.fill",
                tint: Theme.netDeficitBrand,
                title: copy.chargeTitle,
                detail: copy.chargeDetail,
                isLast: true
            )
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "How your free trial works. \(copy.todayTitle). \(copy.todayDetail) \(copy.cancelTitle). \(copy.cancelDetail) \(copy.chargeTitle). \(copy.chargeDetail)"
        )
    }

    private func step(icon: String, tint: Color, title: String, detail: String, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                ZStack {
                    Circle().fill(tint.opacity(0.15)).frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(tint)
                }
                if !isLast {
                    Rectangle()
                        .fill(Theme.textTertiary.opacity(0.25))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(minHeight: isLast ? 28 : 44)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.bottom, isLast ? 0 : 10)
            Spacer(minLength: 0)
        }
    }
}
