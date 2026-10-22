import AntipodesCore
import AntipodesGlobe
import SwiftUI

/// First run: what the app is, what it promises about privacy, and where home is.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @Environment(GlobeBorderStore.self) private var borderStore
    @State private var page = 0
    @State private var isPickingHome = false
    @State private var spin = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Palette.heroGradient.ignoresSafeArea()
            VStack(spacing: 0) {
                Pager(page: $page, count: 3) { index in
                    switch index {
                    case 0: welcome
                    case 1: privacy
                    default: home
                    }
                }
                Button {
                    if page < 2 {
                        withAnimation { page += 1 }
                    } else {
                        model.hasCompletedOnboarding = true
                    }
                } label: {
                    Text(page < 2 ? "Continue" : "Start Exploring")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
        .environment(\.colorScheme, .dark)
        .foregroundStyle(.white)
        .onAppear { borderStore.loadCoarse() }
        .sheet(isPresented: $isPickingHome) {
            PlacePickerSheet(
                title: "Home",
                prompt: "Search your home city",
                kinds: [.city],
                fixedKinds: [.city]
            ) {
                model.home = $0
            }
        }
        .interactiveDismissDisabled()
    }

    private var welcome: some View {
        onboardingPage(
            title: "Every place you've ever been",
            message: """
            Log countries, cities, landmarks and journeys of every kind — then see your \
            travels on a globe and in statistics nobody else offers.
            """
        ) {
            // Turning slowly, unless the user has asked for less motion.
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
                let longitude = (context.date.timeIntervalSinceReferenceDate * 8)
                    .truncatingRemainder(dividingBy: 360) - 180
                GlobeCanvas(
                    scene: .empty,
                    borders: borderStore.coarse,
                    camera: GlobeCamera(
                        centre: Coordinate(latitude: 20, longitude: longitude),
                        zoom: 1
                    ),
                    selection: nil,
                    palette: GlobePalette()
                )
            }
            .accessibilityHidden(true)
        }
    }

    private var privacy: some View {
        onboardingPage(
            title: "Yours alone",
            message: """
            No account. No server. No analytics. Your log stays on this device — nobody \
            else ever sees it, the developer included.
            """
        ) {
            VStack(alignment: .leading, spacing: 22) {
                promise("lock.shield", "Nothing to sign up for")
                promise("wifi.slash", "Search, maps and stats work offline")
                promise("lock", "Stored on this device, nowhere else")
                promise("square.and.arrow.up", "Export everything, any time")
            }
            .font(.body)
        }
    }

    private var home: some View {
        onboardingPage(
            title: "Where's home?",
            message: """
            Home is left out of your days away, and it's where your antipode — the point on \
            exactly the other side of the world — is measured from.
            """
        ) {
            Image(systemName: model.home == nil ? "house" : "house.fill")
                .font(.system(size: 56, weight: .ultraLight))
                .foregroundStyle(Palette.visited)
                .accessibilityHidden(true)
        } actions: {
            VStack(spacing: 10) {
                Button {
                    isPickingHome = true
                } label: {
                    Label(
                        model.home.map { "\($0.flag) \($0.name)" } ?? "Choose Home City",
                        systemImage: "magnifyingglass"
                    )
                    .frame(maxWidth: 280)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                if let antipode = model.home?.coordinate?.antipode {
                    Text("Your antipode is at \(antipode.displayText).")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            historyImports
        }
    }

    /// For someone with years of travel already in another app or in their photos: the
    /// fastest way to a full globe, offered once here and on the empty screens after.
    private var historyImports: some View {
        VStack(spacing: 8) {
            Text("Already keep a log?")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 10) {
                Button("Import Flights", systemImage: "airplane.arrival") {
                    finish(importing: .journeys)
                }
                Button("From Photos", systemImage: "photo.on.rectangle.angled") {
                    finish(importing: .photos)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .padding(.top, 12)
    }

    private func finish(importing request: ImportRequest) {
        model.queuedImport = request
        model.hasCompletedOnboarding = true
    }

    /// One page: art in a band of fixed height, so every title sits at the same place as
    /// the pages turn, then the title, the words, and anything to do below them.
    private func onboardingPage(
        title: String,
        message: String,
        @ViewBuilder art: () -> some View,
        @ViewBuilder actions: () -> some View = { EmptyView() }
    ) -> some View {
        VStack(spacing: 18) {
            art()
                .frame(maxWidth: .infinity)
                .frame(height: 260)
            Text(title)
                .font(.display(.largeTitle))
                .multilineTextAlignment(.center)
            Text(message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.white.opacity(0.75))
            actions()
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .frame(maxWidth: 560)
    }

    private func promise(_ symbol: String, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol)
                .fontWeight(.light)
                .foregroundStyle(Palette.visited)
                .frame(width: 32)
        }
    }
}
