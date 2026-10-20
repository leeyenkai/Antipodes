import AntipodesCore
import AntipodesStats
import SwiftUI

/// The app's colours and type, in one place so the globe, the charts and the cards
/// agree. Colours that carry meaning — a mode, a visit that counts, a wishlist place —
/// are the same everywhere they appear.
enum Palette {
    /// Visited land on the globe, and the brand colour.
    static let visited = Color(red: 0.31, green: 0.78, blue: 0.62)
    static let pin = Color(red: 0.99, green: 0.83, blue: 0.40)
    static let wishlist = Color(red: 0.78, green: 0.62, blue: 0.98)
    static let space = Color(red: 0.02, green: 0.03, blue: 0.07)
    static let warning = Color.orange

    static func mode(_ mode: TravelMode) -> Color {
        switch mode {
        case .flight: Color(red: 1.0, green: 0.58, blue: 0.24)
        case .rail: Color(red: 0.42, green: 0.80, blue: 0.98)
        case .cityTransit: Color(red: 0.55, green: 0.86, blue: 0.66)
        case .coach: Color(red: 0.96, green: 0.76, blue: 0.40)
        case .ferry: Color(red: 0.48, green: 0.62, blue: 1.0)
        case .roadTrip: Color(red: 0.98, green: 0.52, blue: 0.56)
        case .humanPowered: Color(red: 0.74, green: 0.92, blue: 0.42)
        case .cableAndMountain: Color(red: 0.86, green: 0.68, blue: 0.98)
        }
    }

    static func tier(_ tier: AchievementTier?) -> Color {
        switch tier {
        case .bronze: Color(red: 0.80, green: 0.52, blue: 0.30)
        case .silver: Color(red: 0.72, green: 0.76, blue: 0.82)
        case .gold: Color(red: 0.98, green: 0.78, blue: 0.28)
        case .platinum: Color(red: 0.62, green: 0.86, blue: 0.96)
        case nil: visited
        }
    }

    static func archetype(_ archetype: TravelPersonality.Archetype) -> Color {
        switch archetype {
        case .historian: Color(red: 0.86, green: 0.64, blue: 0.38)
        case .trailblazer: Color(red: 0.42, green: 0.80, blue: 0.48)
        case .aesthete: Color(red: 0.86, green: 0.50, blue: 0.80)
        case .pilgrim: Color(red: 0.98, green: 0.82, blue: 0.40)
        case .futurist: Color(red: 0.44, green: 0.72, blue: 1.0)
        case .gourmand: Color(red: 0.98, green: 0.52, blue: 0.40)
        case .wanderer: visited
        }
    }

    /// The backdrop of the hero and share cards: deep space with a hint of the brand.
    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.05, green: 0.10, blue: 0.16),
            Color(red: 0.02, green: 0.03, blue: 0.07),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

extension Font {
    /// Big numbers: rounded, so a dashboard of figures reads friendly rather than
    /// tabular, and monospaced digits so they do not jitter as they animate.
    static func statValue(_ size: CGFloat = 34) -> Font {
        .system(size: size, weight: .bold, design: .rounded).monospacedDigit()
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
            .background(.background.secondary, in: .rect(cornerRadius: 22, style: .continuous))
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
    var lineWidth: CGFloat = 6

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

/// A small coloured symbol tile, used as the leading icon of rows.
struct SymbolTile: View {
    let systemName: String
    var tint: Color = .accentColor
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(tint.gradient, in: .rect(cornerRadius: size * 0.28, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension PlaceKind {
    var tint: Color {
        switch self {
        case .country: Color(red: 0.34, green: 0.62, blue: 0.96)
        case .region: Color(red: 0.46, green: 0.52, blue: 0.94)
        case .city: Palette.visited
        case .landmark: Color(red: 0.96, green: 0.64, blue: 0.30)
        case .airport: Palette.mode(.flight)
        case .route: Palette.mode(.rail)
        case .custom: Color(red: 0.94, green: 0.42, blue: 0.52)
        }
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
