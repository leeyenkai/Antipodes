import AntipodesCore
import Foundation
import SwiftUI

/// How the app looks. Dark by default: the globe is a night-side globe, and the app is
/// designed around it (decision D-20).
public enum AppearancePreference: String, CaseIterable, Identifiable, Sendable {
    case dark
    case light
    case system

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .system: "Match system"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        case .system: nil
        }
    }
}

/// Personal preferences that are not counting rules: appearance, home, first-run state.
///
/// Kept in `UserDefaults` on the device, like the counting rules. Home is a place the
/// user chose, stored as the same reference a visit stores, so it works offline and
/// never needs the database to be read back (R-PRIV-3).
struct PreferencesStorage {
    private enum Key {
        static let appearance = "preferences.appearance"
        static let home = "preferences.home"
        static let onboarded = "preferences.hasCompletedOnboarding"
    }

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var appearance: AppearancePreference {
        get {
            defaults.string(forKey: Key.appearance)
                .flatMap(AppearancePreference.init(rawValue:)) ?? .dark
        }
        nonmutating set {
            defaults.set(newValue.rawValue, forKey: Key.appearance)
        }
    }

    var home: PlaceReference? {
        get {
            defaults.data(forKey: Key.home).flatMap { try? JSONDecoder().decode(
                PlaceReference.self,
                from: $0
            ) }
        }
        nonmutating set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: Key.home)
            } else {
                defaults.removeObject(forKey: Key.home)
            }
        }
    }

    var hasCompletedOnboarding: Bool {
        get { defaults.bool(forKey: Key.onboarded) }
        nonmutating set { defaults.set(newValue, forKey: Key.onboarded) }
    }
}
