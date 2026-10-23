import SwiftUI
@preconcurrency import RevenueCat

/// The exit offer: Vitals+ Yearly at half price, drawn in place of the paywall
/// the customer just closed. One price, one button, one way out. See `ExitOffer`
/// for who sees it and when.
struct ExitOfferView: View {
    let package: Package
    /// Called after "No thanks" or a purchase; the host closes what it was closing.
    let onFinish: () -> Void

    @EnvironmentObject private var store: StoreService
    @State private var isPurchasing = false
    @State private var errorMessage: String?
    /// A purchase answers twice (the result and the `isPro` flip); finish once.
    @State private var finished = false

    private var regularYearly: Package? { store.yearlyPackage }

    /// Off the real store prices, never a hardcoded 50: purchasing-power prices
    /// round to the nearest price point, so a territory may read 49% or 51%.
    private var percentOff: Int? {
        guard let regular = regularYearly?.vitalsPriceAmount, regular > 0 else { return nil }
        let ratio = (package.vitalsPriceAmount / regular as NSDecimalNumber).doubleValue
        let pct = Int(((1 - ratio) * 100).rounded())
        return pct > 0 ? pct : nil
    }

    private var eligibleForTrial: Bool { store.isEligibleForIntroOffer(package) }

    private var headline: String {
        switch percentOff {
        case 50: "Half price on a full year"
        case let pct?: "\(pct)% off a full year"
        case nil: "A full year for less"
        }
    }

    /// The three Vitals+ features shown on the card. None needs food logging,
    /// so the list is true for everyone who closed the paywall.
    private let highlights: [PlusFeature] = [.energyAverages, .deepTrends, .streaks]

    private var ctaTitle: String {
        VitalsConversionCopy.ctaLabel(
            trialLabel: package.vitalsIntroOfferLabel,
            priceLabel: package.vitalsPriceLabel,
            eligibleForTrial: eligibleForTrial
        )
    }

    private var disclosure: String {
        VitalsConversionCopy.disclosure(
            trialLabel: package.vitalsIntroOfferLabel,
            priceLabel: package.vitalsPriceLabel,
            eligibleForTrial: eligibleForTrial
        )
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer(minLength: 12)
                pitch
                Spacer(minLength: 12)
                footer
            }
            .padding(.horizontal, 22)
            .padding(.top, 8)
            .padding(.bottom, 12)
            .readableWidth()
        }
        .interactiveDismissDisabled(isPurchasing)
        .onAppear {
            ExitOffer.recordShown()
            store.trackPaywallImpression(id: ExitOffer.impressionID)
        }
        .onChange(of: store.isPro) { _, isPro in
            if isPro { finish(.purchased) }
        }
    }

    private var pitch: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("ONE-TIME OFFER")
                    .font(.system(.caption, design: .rounded, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(Theme.caloriesPrimary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Theme.caloriesPrimary.opacity(0.12), in: Capsule())

                Text(headline)
                    .font(.system(.title2, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            offerCard
        }
    }

    /// The plan as one object: price first, then what it buys.
    private var offerCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Vitals+ \(package.vitalsDisplayName)")
                    .font(.system(.subheadline, design: .rounded, weight: .bold))
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 8)
                if let percentOff {
                    Text("\(percentOff)% OFF")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.caloriesGradient, in: Capsule())
                }
            }

            priceBlock

            if eligibleForTrial, let days = package.vitalsTrialDayCount {
                Label("Free for the first \(days) days, cancel anytime", systemImage: "checkmark.circle.fill")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.stepsPrimary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                ForEach(highlights, id: \.self) { feature in
                    HStack(spacing: 12) {
                        Image(systemName: feature.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(feature.tint)
                            .frame(width: 22)
                        Text(feature.title)
                            .font(.system(.subheadline, design: .rounded, weight: .medium))
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(width: 22)
                    Text("Every other Vitals+ feature")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .accessibilityElement(children: .combine)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                .stroke(Theme.caloriesPrimary.opacity(0.5), lineWidth: 1.5)
        }
    }

    private var priceBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(package.vitalsLocalizedPriceString)
                    .font(Theme.bigNumber(44))
                    .foregroundStyle(Theme.textPrimary)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("/ year")
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            HStack(spacing: 6) {
                if let regular = regularYearly, percentOff != nil {
                    Text(regular.vitalsLocalizedPriceString)
                        .strikethrough(true, color: Theme.textTertiary)
                        .accessibilityLabel("was \(regular.vitalsLocalizedPriceString)")
                }
                if let perMonth = package.vitalsPricePerMonthLabel {
                    if percentOff != nil { Text("·") }
                    Text("just \(perMonth) a month")
                }
            }
            .font(.system(.subheadline, design: .rounded, weight: .medium).monospacedDigit())
            .foregroundStyle(Theme.textTertiary)
        }
        .accessibilityElement(children: .combine)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Button(action: startPurchase) {
                ZStack {
                    Text(ctaTitle)
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .minimumScaleFactor(0.75)
                        .multilineTextAlignment(.center)
                        .opacity(isPurchasing ? 0 : 1)
                    if isPurchasing {
                        ProgressView().tint(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 13)
                .background(Theme.caloriesGradient, in: Capsule())
                .ctaGlow()
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)
            .accessibilityIdentifier("exit-offer-cta")

            Button {
                finish(.declined)
            } label: {
                Text("No thanks")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing)
            .accessibilityIdentifier("exit-offer-decline")

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(disclosure)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 4) {
                Link("Terms", destination: PaywallLinks.standardEULA)
                Text("·")
                Link("Privacy Policy", destination: PaywallLinks.privacyPolicy)
            }
            .font(.system(.caption2, design: .rounded))
            .foregroundStyle(Theme.textTertiary)
        }
    }

    private func finish(_ outcome: ExitOffer.Outcome) {
        guard !finished else { return }
        finished = true
        ExitOffer.recordOutcome(outcome)
        store.syncConversionAttributes()
        onFinish()
    }

    private func startPurchase() {
        errorMessage = nil
        isPurchasing = true
        Task { @MainActor in
            defer { isPurchasing = false }
            await store.refreshIntroEligibility()
            do {
                switch try await store.purchase(package) {
                case .purchased:
                    finish(.purchased)
                case .pending:
                    errorMessage = store.purchasePendingMessage(for: package)
                case .cancelled:
                    errorMessage = store.purchaseCancelledMessage(for: package)
                case .unavailable:
                    errorMessage = VitalsConversionCopy.purchaseUnavailableMessage
                }
            } catch {
                await store.refreshIntroEligibility()
                errorMessage = store.purchaseFailedMessage(for: package)
            }
        }
    }
}
