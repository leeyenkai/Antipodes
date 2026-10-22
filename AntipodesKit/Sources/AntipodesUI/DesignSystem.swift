import AntipodesCore
import AntipodesStats
import SwiftUI

/// The app's colours and type, in one place so the globe, the charts and the cards
/// agree. Colours that carry meaning — a mode, a visit that counts, a wishlist place —
/// are the same everywhere they appear.
///
/// The palette is deliberately quiet: one sea-glass teal for the brand and for what has
/// been visited, a champagne for pins, and muted, evenly weighted colours for the eight
/// modes. Colour is kept for data; chrome — icons, tiles, section headers — is neutral.
enum Palette {
    /// Visited land on the globe, and the brand colour. The same teal as the app's
    /// accent in both appearances: light on the dark globe and in dark mode, deeper on a
    /// light background, where the light one is too faint to read.
    static let visited = Color(
        light: Color(red: 0.11, green: 0.47, blue: 0.43),
        dark: Color(red: 0.42, green: 0.75, blue: 0.69)
    )
    static let pin = Color(red: 0.95, green: 0.83, blue: 0.60)
    static let wishlist = Color(red: 0.73, green: 0.69, blue: 0.92)
    static let space = Color(red: 0.02, green: 0.03, blue: 0.06)
    /// The faint glow of space nearest the globe.
    static let spaceGlow = Color(red: 0.05, green: 0.08, blue: 0.14)
    static let warning = Color(red: 0.93, green: 0.66, blue: 0.38)

    static func mode(_ mode: TravelMode) -> Color {
        switch mode {
        case .flight: Color(red: 0.96, green: 0.71, blue: 0.47)
        case .rail: Color(red: 0.55, green: 0.74, blue: 0.93)
        case .cityTransit: Color(red: 0.58, green: 0.80, blue: 0.71)
        case .coach: Color(red: 0.87, green: 0.77, blue: 0.56)
        case .ferry: Color(red: 0.50, green: 0.63, blue: 0.90)
        case .roadTrip: Color(red: 0.89, green: 0.60, blue: 0.60)
        case .humanPowered: Color(red: 0.70, green: 0.82, blue: 0.56)
        case .cableAndMountain: Color(red: 0.77, green: 0.68, blue: 0.90)
        }
    }

    static func tier(_ tier: AchievementTier?) -> Color {
        switch tier {
        case .bronze: Color(red: 0.78, green: 0.58, blue: 0.42)
        case .silver: Color(red: 0.74, green: 0.77, blue: 0.81)
        case .gold: Color(red: 0.92, green: 0.79, blue: 0.48)
        case .platinum: Color(red: 0.66, green: 0.82, blue: 0.88)
        case nil: visited
        }
    }

    static func archetype(_ archetype: TravelPersonality.Archetype) -> Color {
        switch archetype {
        case .historian: Color(red: 0.84, green: 0.70, blue: 0.52)
        case .trailblazer: Color(red: 0.56, green: 0.78, blue: 0.58)
        case .aesthete: Color(red: 0.82, green: 0.62, blue: 0.78)
        case .pilgrim: Color(red: 0.92, green: 0.80, blue: 0.56)
        case .futurist: Color(red: 0.56, green: 0.72, blue: 0.92)
        case .gourmand: Color(red: 0.90, green: 0.62, blue: 0.54)
        case .nightOwl: Color(red: 0.62, green: 0.60, blue: 0.90)
        case .wanderer: visited
        }
    }

    /// The backdrop of the hero and share cards: deep space with a hint of the brand.
    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.06, green: 0.10, blue: 0.14),
            Color(red: 0.02, green: 0.03, blue: 0.06),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

/// Corner radii, so cards, panels and thumbnails round alike. Content cards are one
/// size, the glass that floats over the globe another, small chips a third.
enum Radius {
    /// A content card: a stat card, a trip's header, a year's tile, a share preview.
    static let card: CGFloat = 20
    /// Glass floating over the globe: the summary bar, the empty-state panel, the drop
    /// target.
    static let panel: CGFloat = 26
    /// A tile or thumbnail inside a row: a trip's little globe, a mode tile.
    static let tile: CGFloat = 14
    /// A one-line chip or caveat.
    static let chip: CGFloat = 12
}

extension Color {
    /// One colour in light appearance and another in dark, resolved wherever it is
    /// drawn — so a view forced dark, like the globe, takes the dark one.
    init(light: Color, dark: Color) {
        #if os(iOS)
            self.init(uiColor: UIColor { traits in
                traits.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
            })
        #else
            self.init(nsColor: NSColor(name: nil) { appearance in
                appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                    ? NSColor(dark) : NSColor(light)
            })
        #endif
    }
}

// MARK: - Type (D-34)

/// The app's type: SF Pro on the system's text styles, so it follows Dynamic Type, with
/// New York for one role only. Named here so every screen reaches for the same few
/// rather than inventing a size; AGENTS.md lists the roles and `scripts/lint.sh` refuses
/// a raw point size outside this file and the image renderers.
///
/// | Role | Font |
/// |---|---|
/// | `display` | New York — a personality, an onboarding page, Year in Review, a share card |
/// | `sectionTitle` | Title 3, semibold — a group of figures |
/// | `figure(_:)` | SF Pro, even-width digits, scaled with the text size |
/// | `Eyebrow` | Caption 2, semibold, upper case, tracked — the label above a figure |
///
/// Body, subheadline, footnote and caption are the system's own. Text weights are
/// regular, medium, semibold and bold; lighter weights are for symbols only.
extension Font {
    /// Display titles — a personality, a year, the first words a page says — in New
    /// York, the system serif: a travel journal's voice, kept to those moments so it
    /// stays one.
    static func display(_ style: Font.TextStyle = .largeTitle) -> Font {
        .system(style, design: .serif, weight: .regular)
    }

    /// The heading of a group of figures.
    static let sectionTitle = Font.title3.weight(.semibold)

    /// A figure drawn into an image — a share card, a frame of the Year in Review film —
    /// at the fixed size the image is laid out for: an image cannot follow the reader's
    /// text size, and should look the same wherever it is sent.
    static func renderedFigure(_ role: FigureRole, size: CGFloat) -> Font {
        .system(size: size, weight: role.weight).monospacedDigit()
    }

    /// A symbol used as a picture rather than beside text, at a size the layout fixes.
    static func icon(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

/// How prominent a figure is. Each role has one size and one weight, and scales with
/// the text style it stands in for, so a dashboard of numbers lines up — even-width
/// digits — and grows with the reader's text size instead of staying put.
enum FigureRole {
    /// The one number a full-screen card is about: a year in review.
    case showcase
    /// The number a page leads with: a collection's progress, the carbon total.
    case hero
    /// A stat card's number.
    case card
    /// A number in a row of three: a trip's header.
    case inline

    var size: CGFloat {
        switch self {
        case .showcase: 64
        case .hero: 44
        case .card: 28
        case .inline: 20
        }
    }

    var weight: Font.Weight {
        switch self {
        case .showcase, .hero, .card: .regular
        case .inline: .medium
        }
    }

    var textStyle: Font.TextStyle {
        switch self {
        case .showcase, .hero: .largeTitle
        case .card: .title
        case .inline: .title3
        }
    }
}

private struct FigureFont: ViewModifier {
    let role: FigureRole
    @ScaledMetric private var size: CGFloat

    init(_ role: FigureRole) {
        self.role = role
        _size = ScaledMetric(wrappedValue: role.size, relativeTo: role.textStyle)
    }

    func body(content: Content) -> some View {
        content
            .font(.system(size: size, weight: role.weight).monospacedDigit())
            // The biggest roles stop growing before they push the rest off the screen.
            .dynamicTypeSize(...(role == .card || role == .inline ? .accessibility3 :
                    .accessibility1))
    }
}

extension View {
    /// A number in one of the app's figure roles, scaled with the text size.
    func figure(_ role: FigureRole) -> some View {
        modifier(FigureFont(role))
    }
}

/// A small caption above a figure or a group: upper case, tracked, secondary.
struct Eyebrow: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

/// A grouped card: the content layer, so not glass (glass is for the controls that
/// float over content).
struct CardBackground: ViewModifier {
    var padding: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                .background.secondary,
                in: .rect(cornerRadius: Radius.card, style: .continuous)
            )
    }
}

extension View {
    func card(padding: CGFloat = 16) -> some View {
        modifier(CardBackground(padding: padding))
    }
}

/// A circular progress ring, for achievements and collections.
struct ProgressRing: View {
    let progress: Double
    var tint: Color = Palette.visited
    var lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.18), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .animation(.smooth, value: progress)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue(Format.percent(progress, digits: 0))
    }
}

/// The leading icon of a row: a symbol on a quiet neutral tile. The symbol takes the
/// row's colour only where the colour means something — a journey's mode — and is
/// secondary otherwise.
struct SymbolTile: View {
    let systemName: String
    var tint: Color = .secondary
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemName)
            .font(.icon(size * 0.46))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(.fill.tertiary, in: .rect(cornerRadius: size * 0.3, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension PlaceKind {
    /// Places are told apart by their symbol, so their tiles stay neutral.
    var tint: Color {
        .secondary
    }
}

/// Ends text editing anywhere in the window, so a field lets go of what it is bound to.
@MainActor
func endEditing() {
    #if os(iOS)
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    #elseif os(macOS)
        NSApp.keyWindow?.makeFirstResponder(nil)
    #endif
}

extension View {
    /// Word capitalisation for name fields, where the platform has it.
    func capitalizingWords() -> some View {
        #if os(iOS)
            textInputAutocapitalization(.words)
        #else
            self
        #endif
    }

    /// Upper-case input for codes such as flight numbers and registrations.
    func capitalizingCharacters() -> some View {
        #if os(iOS)
            textInputAutocapitalization(.characters).autocorrectionDisabled()
        #else
            autocorrectionDisabled()
        #endif
    }

    /// Numbers with a minus sign, for coordinates: the decimal pad has no minus key, so
    /// south and west could not be typed.
    func signedDecimalKeyboard() -> some View {
        #if os(iOS)
            keyboardType(.numbersAndPunctuation).autocorrectionDisabled()
        #else
            self
        #endif
    }

    /// A numeric keyboard where there is one.
    func decimalKeyboard() -> some View {
        #if os(iOS)
            keyboardType(.decimalPad)
        #else
            self
        #endif
    }
}
