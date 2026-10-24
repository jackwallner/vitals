import CoreGraphics
#if os(iOS)
import SwiftUI
#endif

/// Pane frames for the unfolded iPhone Duo: the tabs on the leading side of the
/// fold, History on the trailing side, so no card straddles the crease. `nil`
/// keeps the single-column layout (every ordinary iPhone, the folded Duo, and
/// the unfolded Duo held in portrait, where each half would be too narrow).
struct UnfoldedSplit: Equatable, Sendable {
    var primaryWidth: CGFloat
    var secondaryX: CGFloat
    var secondaryWidth: CGFloat

    /// Narrowest pane that still fits the compact Today and History layouts.
    static let minimumPaneWidth: CGFloat = 360

    /// - Parameters:
    ///   - width: the container's width.
    ///   - fold: the vertical fold's leading and trailing edge in the same
    ///     coordinate space, or `nil` when the system reports none.
    static func make(width: CGFloat, isRegularWidth: Bool, fold: ClosedRange<CGFloat>?) -> UnfoldedSplit? {
        guard isRegularWidth, width >= minimumPaneWidth * 2 else { return nil }
        if let fold,
           fold.lowerBound >= minimumPaneWidth,
           width - fold.upperBound >= minimumPaneWidth {
            return UnfoldedSplit(
                primaryWidth: fold.lowerBound,
                secondaryX: fold.upperBound,
                secondaryWidth: width - fold.upperBound
            )
        }
        let half = (width / 2).rounded(.down)
        return UnfoldedSplit(primaryWidth: half, secondaryX: half, secondaryWidth: width - half)
    }

    /// The primary pane's top inset. Unfolded, the tab bar heads the leading
    /// pane, so the pane starts below it and, like History, runs to the
    /// display's bottom edge: no card is cut off against a docked bar. Folded,
    /// the bar floats at the bottom and the pane fills the screen.
    static func primaryTopInset(_ split: UnfoldedSplit?, tabBarHeight: CGFloat) -> CGFloat {
        split == nil ? 0 : tabBarHeight
    }
}

#if os(iOS)
extension EnvironmentValues {
    /// True inside one pane of the unfolded split. The tab bar sits above the
    /// leading pane there, so scroll views drop the clearance they keep for a
    /// floating bar, and Settings opens in its pane rather than as a sheet over both.
    @Entry var isUnfoldedPane = false
}

extension GeometryProxy {
    /// The vertical fold's horizontal extent in this proxy's space. Inactive
    /// folds count too, so the panes don't jump while the device opens.
    func verticalFold() -> ClosedRange<CGFloat>? {
        guard #available(iOS 27.1, *) else { return nil }
        let fold = reservedRegions(kind: .division, options: .includeInactive)
            .map(\.frame)
            .first { $0.height > $0.width && $0.minX > 0 && $0.maxX < size.width }
        guard let fold else { return nil }
        return fold.minX...fold.maxX
    }
}
#endif
