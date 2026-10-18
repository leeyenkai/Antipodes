import SwiftUI

/// The app's navigation shell.
///
/// `.sidebarAdaptable` gives tabs on iPhone and a sidebar on iPad and Mac from one
/// declaration, which is what §9 asks for without a per-platform fork.
public struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var isAddingPlace = false

    public init() {}

    public var body: some View {
        TabView {
            Tab("Globe", systemImage: "globe") {
                GlobeScreen()
            }
            Tab("Trips", systemImage: "suitcase") {
                TripsScreen()
            }
            Tab("Stats", systemImage: "chart.bar") {
                StatsScreen()
            }
            Tab("Settings", systemImage: "gearshape") {
                SettingsScreen()
            }
        }
        .tabViewStyle(.sidebarAdaptable)
        .overlay(alignment: .bottomTrailing) {
            AddButton { isAddingPlace = true }
        }
        .sheet(isPresented: $isAddingPlace) {
            AddSheet()
        }
    }
}

/// The persistent add button (§9).
///
/// Logging is the one thing that must be reachable from anywhere in one thumb
/// movement, so it floats rather than living inside a screen.
private struct AddButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .padding(.trailing, 20)
        .padding(.bottom, 72)
        .accessibilityLabel("Log a place or journey")
    }
}
