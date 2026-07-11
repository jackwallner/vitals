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
            if request.plan == .trial {
                trialBackdrop {
                    TrialOfferSheet(
                        focus: focus,
                        offerLabel: store.canPitchFreeTrial
                            ? (trialPackage?.vitalsIntroOfferLabel ?? "7-day free trial")
                            : nil,
                        priceLabel: trialPackage?.vitalsPriceLabel ?? "$29.99 / year",
                        ctaTitle: store.onboardingTrialCTALabel,
                        disclosureText: store.yearlySheetDisclosureText
                            ?? "\(trialPackage?.vitalsPriceLabel ?? "$29.99 / year"). Auto-renews unless cancelled 24h before the period ends.",
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

    private var trialPackage: Package? {
        store.products.first { $0.vitalsPackageKind == .yearly } ?? store.products.first
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
