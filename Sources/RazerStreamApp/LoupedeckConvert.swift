import Foundation

// Turns a parsed Loupedeck profile into one of ours, along with a list of
// everything that needs a human decision. The conversion never invents an
// action: a control that could not be translated arrives with its label and
// icon intact but no action bound, so the deck reads correctly and the tile
// is ready to be reassigned.

/// The app's own profile type. Inside `extension LoupedeckImport` the bare
/// name `Profile` refers to the Loupedeck one, so this alias keeps the two
/// unambiguous wherever both appear.
typealias DeckProfile = Profile
typealias DeckPage = Page

extension LoupedeckImport {

    /// One control the review step should ask about.
    struct ReviewItem: Identifiable {
        let id = UUID()
        var pageIndex: Int
        var pageName: String
        /// Where it sits, e.g. "Tile 3 (row 1, col 3)" or "Knob 2 turn".
        var location: String
        var label: String
        /// Why it needs attention: the unmapped reason, or the approximation note.
        var detail: String
        /// True when something was bound but is worth checking; false when
        /// nothing was bound at all.
        var isApproximate: Bool
    }

    struct ImportResult {
        var profile: DeckProfile
        var review: [ReviewItem]
        var mappedCount: Int
        var approximateCount: Int
        var unmappedCount: Int

        var totalAssigned: Int { mappedCount + approximateCount + unmappedCount }
    }

    /// Builds a profile from a Loupedeck one. `tilesPerPage` and `knobCount`
    /// come from our hardware rather than the source, since another device's
    /// profile can carry a different number of controls (a Loupedeck CT page
    /// holds 15); extra controls are reported rather than dropped silently.
    static func convert(_ source: LoupedeckImport.Profile, named name: String) -> ImportResult {
        let tilesPerPage = 12
        let knobCount = 6

        guard let mode = primaryMode(of: source) else {
            return ImportResult(profile: DeckProfile(name: name, pages: [DeckPage(name: "Page 1")]),
                                review: [], mappedCount: 0, approximateCount: 0, unmappedCount: 0)
        }

        let translator = Translator(profile: source)
        var review: [ReviewItem] = []
        var mapped = 0, approximate = 0, unmapped = 0

        /// Records the outcome and returns the action to bind, if any.
        func resolve(_ raw: String?,
                     pageIndex: Int,
                     pageName: String,
                     location: String) -> (action: ControlAction, label: String)? {
            guard let raw else { return nil }
            let t = translator.translate(raw)
            switch t.mapping {
            case .empty:
                return nil
            case .mapped(let a):
                mapped += 1
                return (a, t.label)
            case .approximate(let a, let note):
                approximate += 1
                review.append(ReviewItem(pageIndex: pageIndex, pageName: pageName,
                                         location: location, label: t.label,
                                         detail: note, isApproximate: true))
                return (a, t.label)
            case .unmapped(let reason):
                unmapped += 1
                review.append(ReviewItem(pageIndex: pageIndex, pageName: pageName,
                                         location: location, label: t.label,
                                         detail: reason, isApproximate: false))
                // Keep the label so the tile still reads correctly.
                return (.none, t.label)
            }
        }

        // Knobs live on their own page in Loupedeck but are per page for us,
        // so the first encoder page is applied to every page we create.
        let sourceKnobs = (mode.encoderPages?.first?.controls ?? [])

        var pages: [DeckPage] = []
        for (pageIndex, sourcePage) in (mode.touchPages ?? []).enumerated() {
            let pageName = sourcePage.displayName ?? "Page \(pageIndex + 1)"
            var page = DeckPage(name: pageName)

            let controls = sourcePage.controls ?? []
            if controls.count > tilesPerPage {
                review.append(ReviewItem(
                    pageIndex: pageIndex, pageName: pageName,
                    location: "Page",
                    label: pageName,
                    detail: "The original page had \(controls.count) tiles; this deck has \(tilesPerPage), so the last \(controls.count - tilesPerPage) were left out",
                    isApproximate: false))
            }

            for (i, control) in controls.prefix(tilesPerPage).enumerated() {
                let row = i / 4 + 1, col = i % 4 + 1
                guard let r = resolve(control.pressAction,
                                      pageIndex: pageIndex, pageName: pageName,
                                      location: "Tile \(i + 1) (row \(row), col \(col))")
                else { continue }
                page.tiles[i].label = r.label
                page.tiles[i].action = r.action
            }

            for (i, control) in sourceKnobs.prefix(knobCount).enumerated() {
                let turn = resolve(control.rotateAction,
                                   pageIndex: pageIndex, pageName: pageName,
                                   location: "Knob \(i + 1) turn")
                let press = resolve(control.pressAction,
                                    pageIndex: pageIndex, pageName: pageName,
                                    location: "Knob \(i + 1) press")

                if let turn {
                    // Loupedeck stores turning as a single bidirectional
                    // adjustment ("Volume"), while ours is a clockwise and a
                    // counter-clockwise action. Translating gives us only the
                    // increase half, so widen it back into the matching preset
                    // pair; without this the knob would work one way only.
                    if let preset = Self.rotationPreset(for: turn.action) {
                        let pair = KnobRotationMode.actions(
                            for: preset, clockwiseIncreases: KnobDirection.clockwiseIncreases)
                        page.knobs[i].clockwise = pair.clockwise
                        page.knobs[i].counterClockwise = pair.counterClockwise
                    } else {
                        page.knobs[i].clockwise = turn.action
                    }
                    if page.knobs[i].label.isEmpty { page.knobs[i].label = turn.label }
                }
                if let press {
                    page.knobs[i].press = press.action
                    if page.knobs[i].label.isEmpty { page.knobs[i].label = press.label }
                }
            }

            pages.append(page)
        }

        if pages.isEmpty { pages = [DeckPage(name: "Page 1")] }

        var profile = DeckProfile(name: name)
        profile.pages = pages
        return ImportResult(profile: profile, review: review,
                            mappedCount: mapped, approximateCount: approximate,
                            unmappedCount: unmapped)
    }

    /// The rotation preset a single "increase" action belongs to, so a
    /// one-directional import can be widened into the proper pair. Returns
    /// nil for actions that are not half of a bidirectional pair, which are
    /// then bound to the clockwise direction alone.
    private static func rotationPreset(for action: ControlAction) -> KnobRotationMode? {
        switch action {
        case .volumeUp, .volumeDown:                 return .volume
        case .brightnessUp, .brightnessDown:         return .brightness
        case .ledBrightnessUp, .ledBrightnessDown:   return .ledBrightness
        case .bothBrightnessUp, .bothBrightnessDown: return .combinedBrightness
        case .nextPage, .prevPage:                   return .pageNavigation
        case .mediaNext, .mediaPrevious:             return .mediaTrack
        case .mouseScrollUp, .mouseScrollDown:       return .mouseScrollVertical
        case .mouseScrollLeft, .mouseScrollRight:    return .mouseScrollHorizontal
        default:                                     return nil
        }
    }
}
