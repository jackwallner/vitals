import SwiftUI
@preconcurrency import RevenueCat

/// The exit offer as it appears in place: the usual yearly price beside the
/// half price, dropped into the pitch the customer was about to leave. The
/// page around it stays put; its button buys this plan and its way out becomes
/// "No thanks". See `ExitOffer` for who sees it and when.
///
/// Appearing is the impression, so every surface records it the same way.
struct ExitOfferPriceTiles: View {
    let offer: Package
    /// The regular yearly plan, for the struck-through price. nil hides that tile.
    let regular: Package?

    @EnvironmentObject private var store: StoreService
    @Environment(\.enclosingScrollReader) private var scrollReader

    static let scrollID = "exit-offer-tiles"

    /// Off the real store prices, never a hardcoded 50: purchasing-power prices
    /// round to the nearest price point, so a territory may read 49% or 51%.
    private var percentOff: Int? {
        guard let regular = regular?.vitalsPriceAmount, regular > 0 else { return nil }
        let ratio = (offer.vitalsPriceAmount / regular as NSDecimalNumber).doubleValue
        let pct = Int(((1 - ratio) * 100).rounded())
        return pct > 0 ? pct : nil
    }

    private var badge: String {
        switch percentOff {
        case 50: "HALF OFF"
        case let pct?: "\(pct)% OFF"
        case nil: "OFFER"
        }
    }

    private var accessibilitySummary: String {
        let offerPrice = "\(offer.vitalsLocalizedPriceString) a year"
        guard let regular, percentOff != nil else { return "Your price, \(offerPrice)" }
        return "Your price, \(offerPrice), usually \(regular.vitalsLocalizedPriceString)"
    }

    var body: some View {
        HStack(spacing: 10) {
            if let regular, percentOff != nil {
                tile(
                    label: "Usual price",
                    labelColor: Theme.textSecondary,
                    price: Text(regular.vitalsLocalizedPriceString).strikethrough(true, color: Theme.textTertiary),
                    priceColor: Theme.textTertiary
                )
                .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            tile(
                // Not "One-time price": it renews at this price every year,
                // and the disclosure under it says so.
                label: "Your price",
                labelColor: Theme.caloriesPrimary,
                price: Text(offer.vitalsLocalizedPriceString),
                priceColor: Theme.textPrimary
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Theme.caloriesPrimary, lineWidth: 2)
            }
            .overlay(alignment: .top) {
                Text(badge)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Theme.caloriesPrimary, in: Capsule())
                    .offset(y: -10)
            }
        }
        .padding(.top, 10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
        .accessibilityIdentifier("exit-offer-tiles")
        .id(Self.scrollID)
        .onAppear {
            ExitOffer.recordShown()
            store.trackPaywallImpression(id: ExitOffer.impressionID)
            // At large text sizes the page scrolls, and the tiles land under
            // the fold: the button and disclosure changed with nothing on
            // screen saying why. Wait one pass so they have a frame to scroll to.
            guard let scrollReader else { return }
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) {
                    scrollReader.scrollTo(Self.scrollID, anchor: .bottom)
                }
            }
        }
    }

    private func tile(label: String, labelColor: Color, price: Text, priceColor: Color) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(.caption, design: .rounded, weight: .semibold))
                .foregroundStyle(labelColor)
            price
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(priceColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("per year")
                .font(.system(.caption2, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
}

extension EnvironmentValues {
    /// The scroll view a child sits in, so it can scroll itself into view. nil
    /// outside one that opted in with `revealingInScroll(_:)`.
    @Entry var enclosingScrollReader: ScrollViewProxy? = nil
}

extension View {
    /// Lets children scroll themselves into view in `reader`, the way the exit
    /// offer tiles do when they slide in below the fold.
    func revealingInScroll(_ reader: ScrollViewProxy) -> some View {
        environment(\.enclosingScrollReader, reader)
    }
}
