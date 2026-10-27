#if DEBUG
import SwiftUI
@preconcurrency import RevenueCat

struct PaywallScreenshotHarness: View {
    let request: PaywallSnapshotRequest
    @StateObject private var store = StoreService.shared

    private var focus: PlusFeature? {
        request.focusSlug.flatMap { PlusFeature.fromSnapshotSlug($0) }
    }

    var body: some View {
        Group {
            if request.plan == .exit {
                if request.focusSlug == "sheet" {
                    trialBackdrop { exitOfferSheet }
                } else {
                    PaywallView(displayCloseButton: true, focus: focus)
                }
            } else if request.plan == .trial {
                trialBackdrop {
                    TrialOfferSheet(
                        focus: focus,
                        offerLabel: store.canPitchFreeTrial
                            ? (trialPackage?.vitalsIntroOfferLabel ?? String(localized: "7-day free trial"))
                            : nil,
                        priceLabel: trialPackage?.vitalsPriceLabel ?? "$6.99 / month",
                        ctaTitle: store.onboardingTrialCTALabel,
                        disclosureText: store.onboardingTrialDisclosureText
                            ?? String(localized: "\(trialPackage?.vitalsPriceLabel ?? "$6.99 / month"). Auto-renews unless cancelled 24h before the period ends."),
                        directPurchase: true,
                        isPurchasing: false,
                        errorMessage: nil,
                        onStartTrial: {},
                        onDismiss: {}
                    )
                }
            } else {
                PaywallView(displayCloseButton: false, focus: focus)
            }
        }
        .environmentObject(store)
        .task {
            if store.products.isEmpty { await store.fetchProducts() }
        }
    }

    /// The exit offer's own sheet, as `MainTabView` raises it.
    @ViewBuilder
    private var exitOfferSheet: some View {
        if let offer = store.exitOfferPackage {
            TrialOfferSheet(
                focus: nil,
                headlineOverride: ExitOfferPriceTiles.headline(offer: offer, regular: store.regularYearlyPackage),
                subheadlineOverride: ExitOffer.welcomeLine(endsAt: Date.now.addingTimeInterval(ExitOffer.welcomeWindow)),
                offerLabel: offer.vitalsIntroOfferLabel,
                priceLabel: offer.vitalsPriceLabel,
                ctaTitle: store.ctaLabel(for: offer),
                disclosureText: VitalsConversionCopy.sheetDisclosure(
                    trialLabel: offer.vitalsIntroOfferLabel,
                    priceLabel: offer.vitalsPriceLabel,
                    eligibleForTrial: store.isEligibleForIntroOffer(offer)
                ),
                directPurchase: true,
                isPurchasing: false,
                errorMessage: nil,
                onStartTrial: {},
                onDismiss: {},
                exitOffer: offer,
                exitOfferRegular: store.regularYearlyPackage,
                recordsExitOfferImpression: false
            )
        } else {
            // A non-empty view, so `.task` below runs and loads the plan.
            ProgressView()
        }
    }

    private var trialPackage: Package? {
        store.products.first { $0.vitalsPackageKind == .monthly } ?? store.products.first
    }

    private func trialBackdrop<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack {
                Spacer()
                content()
                    .frame(maxHeight: UIScreen.main.bounds.height * 0.68)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 6)
            }
        }
    }
}
#endif
