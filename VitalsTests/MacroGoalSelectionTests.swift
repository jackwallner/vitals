import XCTest

/// Macro targets are a per-macro decision: someone can chase a protein number
/// while carbs and fat stay a plain readout on the same card.
final class MacroGoalSelectionTests: XCTestCase {

    private let all = Set(MacroKind.allCases)

    func testGoalsOffMeansEverythingIsAPill() {
        XCTAssertEqual(MacroGoalSelection.goaled(enabled: false, goaled: all, visible: all), [])
        XCTAssertEqual(
            MacroGoalSelection.ungoaled(enabled: false, goaled: all, visible: all),
            [.protein, .carbs, .fat]
        )
    }

    func testProteinOnlyGoalLeavesCarbsAndFatAsPills() {
        XCTAssertEqual(
            MacroGoalSelection.goaled(enabled: true, goaled: [.protein], visible: all),
            [.protein]
        )
        XCTAssertEqual(
            MacroGoalSelection.ungoaled(enabled: true, goaled: [.protein], visible: all),
            [.carbs, .fat]
        )
    }

    func testBothListsStayInCanonicalOrder() {
        XCTAssertEqual(
            MacroGoalSelection.goaled(enabled: true, goaled: [.fat, .protein], visible: all),
            [.protein, .fat]
        )
        XCTAssertEqual(
            MacroGoalSelection.ungoaled(enabled: true, goaled: [.carbs], visible: all),
            [.protein, .fat]
        )
    }

    /// A goal on a macro the user has hidden must not draw a bar for a macro
    /// that isn't on the card at all.
    func testHiddenMacrosAreNeitherBarredNorPilled() {
        XCTAssertEqual(
            MacroGoalSelection.goaled(enabled: true, goaled: all, visible: [.carbs]),
            [.carbs]
        )
        XCTAssertEqual(
            MacroGoalSelection.ungoaled(enabled: true, goaled: all, visible: [.carbs]),
            []
        )
        XCTAssertEqual(
            MacroGoalSelection.ungoaled(enabled: true, goaled: [.protein], visible: [.carbs, .fat]),
            [.carbs, .fat]
        )
    }

    func testEveryVisibleMacroLandsInExactlyOneList() {
        for enabled in [true, false] {
            for goaled in powerSet(MacroKind.allCases) {
                for visible in powerSet(MacroKind.allCases) where !visible.isEmpty {
                    let bars = MacroGoalSelection.goaled(enabled: enabled, goaled: goaled, visible: visible)
                    let pills = MacroGoalSelection.ungoaled(enabled: enabled, goaled: goaled, visible: visible)
                    XCTAssertEqual(
                        Set(bars).union(pills), visible,
                        "every visible macro renders, goals \(enabled ? "on" : "off")"
                    )
                    XCTAssertTrue(
                        Set(bars).isDisjoint(with: pills),
                        "a macro can't be both a bar and a pill"
                    )
                }
            }
        }
    }

    func testLastGoalCannotBeSwitchedOff() {
        XCTAssertFalse(MacroGoalSelection.canDisableGoal(enabled: true, goaled: [.protein], visible: all))
        XCTAssertTrue(MacroGoalSelection.canDisableGoal(enabled: true, goaled: [.protein, .carbs], visible: all))
        // Two goals but only one of them visible is still the last one standing.
        XCTAssertFalse(
            MacroGoalSelection.canDisableGoal(enabled: true, goaled: [.protein, .carbs], visible: [.protein])
        )
    }

    private func powerSet(_ kinds: [MacroKind]) -> [Set<MacroKind>] {
        (0..<(1 << kinds.count)).map { mask in
            Set(kinds.enumerated().compactMap { mask & (1 << $0.offset) == 0 ? nil : $0.element })
        }
    }
}
