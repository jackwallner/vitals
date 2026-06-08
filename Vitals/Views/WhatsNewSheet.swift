import SwiftUI

/// One-time announcement shown to existing users after they update to the build
/// that introduced the opt-in Vitals+ extras. It is purely an awareness surface:
/// the core Today view and every default are unchanged, and nothing here flips a
/// feature on. Non-subscribers get a "Try Vitals+ free" path; subscribers get an
/// "Open Settings" path so they choose which extras to enable. Either way the
/// user stays in control.
struct WhatsNewSheet: View {
    let isPro: Bool
    /// Non-Pro primary CTA — routes to the trial offer.
    let onTryFree: () -> Void
    /// Pro primary CTA — opens Settings so they can pick extras to switch on.
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animateGlow = false

    /// The extras to advertise, newest-feeling first. Pulled straight from
    /// `PlusFeature` so the copy stays in sync with the paywall and settings.
    private let features: [PlusFeature] = [.projections, .streaks, .weeklyRecap, .netDeficit]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 18) {
                        hero
                            .padding(.top, 28)

                        VStack(spacing: 6) {
                            Text("New in Total Calories")
                                .font(.system(.title2, design: .rounded, weight: .bold))
                                .foregroundStyle(Theme.textPrimary)
                                .multilineTextAlignment(.center)
                            Text("A few optional Vitals+ extras, now tucked right next to the metrics they belong with. Everything you already use stays exactly the same — these are off until you switch them on.")
                                .font(.system(.subheadline, design: .rounded))
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .padding(.horizontal, 12)
                        }

                        VStack(spacing: 10) {
                            ForEach(features, id: \.self) { feature in
                                WhatsNewFeatureRow(feature: feature)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 16)
                }

                footerCTAs
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
                animateGlow = true
            }
        }
    }

    private var hero: some View {
        ZStack {
            Circle()
                .fill(Theme.caloriesGradient)
                .frame(width: 72, height: 72)
                .shadow(color: Theme.caloriesPrimary.opacity(0.4), radius: 14, x: 0, y: 6)
                .scaleEffect(animateGlow ? 1.05 : 0.97)
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white)
                .rotationEffect(.degrees(animateGlow ? 5 : -5))
        }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var footerCTAs: some View {
        VStack(spacing: 10) {
            Button(action: isPro ? onOpenSettings : onTryFree) {
                Text(isPro ? "Choose in Settings" : "Try Vitals+ Free")
                    .font(.system(.headline, design: .rounded, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(Theme.caloriesGradient, in: Capsule())
            }
            .buttonStyle(.plain)

            Button(action: onDismiss) {
                Text("Not now")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            if !isPro {
                Text("Extras stay off until you turn them on.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 16)
        .background(.ultraThinMaterial)
    }
}

private struct WhatsNewFeatureRow: View {
    let feature: PlusFeature

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Circle()
                    .fill(feature.tint.opacity(0.18))
                    .frame(width: 36, height: 36)
                Image(systemName: feature.icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(feature.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(feature.title)
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(feature.detail)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(feature.title). \(feature.detail)")
    }
}
