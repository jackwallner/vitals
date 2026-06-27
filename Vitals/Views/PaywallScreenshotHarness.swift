#if DEBUG
import SwiftUI
@preconcurrency import RevenueCat

struct PaywallScreenshotHarness: View {
    let mode: PaywallScreenshotMode
    @StateObject private var store = StoreService.shared

    var body: some View {
        Group {
            if mode == .trial {
                trialBackdrop {
                    TrialOfferSheet(
                        focus: nil,
                        offerLabel: trialPackage?.vitalsIntroOfferLabel ?? "7-day free trial",
                        priceLabel: trialPackage?.vitalsPriceLabel ?? "$29.99 / year",
                        directPurchase: true,
                        isPurchasing: false,
                        errorMessage: nil,
                        onStartTrial: {},
                        onSeeAllPlans: {},
                        onDismiss: {}
                    )
                }
            } else {
                PaywallView(displayCloseButton: false)
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
