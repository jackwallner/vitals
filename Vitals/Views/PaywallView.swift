import SwiftUI
@preconcurrency import RevenueCat
import RevenueCatUI

/// Static URLs surfaced from the paywall — Apple requires both an EULA (we use the
/// standard one) and a Privacy Policy link before the StoreKit purchase buttons.
/// Kept here so any other surface in the app can link to the same destinations.
enum PaywallLinks {
    static let privacyPolicy = URL(string: "https://jackwallner.github.io/vitals/privacy-policy.html")!
    static let standardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

/// Thin wrapper around the RevenueCat-hosted paywall (`RevenueCatUI.PaywallView`).
/// The visual design lives in the RevenueCat dashboard — see
/// `_handoffs/revenuecat-paywall-handoff.md` for the spec used to author it.
///
/// Dismisses itself when the user becomes pro so callers can present this in a
/// sheet without wiring any custom completion handler.
struct PaywallView: View {
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss

    /// Set to `false` when this view is rendered as tab content rather than in a
    /// sheet — the tab bar handles navigation so a built-in close button looks off.
    var displayCloseButton: Bool = true

    var body: some View {
        RevenueCatUI.PaywallView(displayCloseButton: displayCloseButton)
            .onPurchaseCompleted { _ in
                Task { await store.updateCustomerProductStatus(fetchPolicy: .fetchCurrent) }
            }
            .onRestoreCompleted { _ in
                Task { await store.updateCustomerProductStatus(fetchPolicy: .fetchCurrent) }
            }
            .onChange(of: store.isPro) { _, isPro in
                if isPro { dismiss() }
            }
    }
}
