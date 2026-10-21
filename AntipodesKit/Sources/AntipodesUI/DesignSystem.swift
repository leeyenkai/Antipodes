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
    /// Visited land on the globe, and the brand colour.
    static let visited = Color(red: 0.42, green: 0.75, blue: 0.69)
    static let pin = Color(red: 0.95, green: 0.83, blue: 0.60)
    static let wishlist = Color(red: 0.73, green: 0.69, blue: 0.92)
    static let space = Color(red: 0.02, green: 0.03, blue: 0.06)
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

extension Font {
    /// Figures: SF Pro with even-width digits, so a dashboard of numbers lines up and
    /// does not jitter as it animates. Lighter as it grows — a large figure reads
    /// better light than heavy.
    static func statValue(_ size: CGFloat = 34) -> Font {
        let weight: Font.Weight = switch size {
        case 44...: .light
        case 26...: .regular
        default: .medium
        }
        return .system(size: size, weight: weight).monospacedDigit()
    }

    /// Display titles — a personality, a year, the first words a screen says — in New
    /// York, the system serif: a travel journal's voice, used sparingly.
    static func display(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif, weight: weight)
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
            .background(.background.secondary, in: .rect(cornerRadius: 20, style: .continuous))
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
            .font(.system(size: size * 0.46, weight: .regular))
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
