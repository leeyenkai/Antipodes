import AntipodesCore
import AntipodesExport
import AntipodesPlaces
import AntipodesStore
import SwiftUI
import UniformTypeIdentifiers

/// The counting rules in plain words, so a number is never a mystery.
struct CountingExplainer: View {
    var body: some View {
        List {
            Section("Visit types") {
                ForEach(VisitType.allCases) { type in
                    Label {
                        VStack(alignment: .leading) {
                            Text(type.displayName)
                            Text(type.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: type.symbolName)
                    }
                }
            }
            Section("Rules") {
                Text("""
                A landmark counts its city, region and country. A city counts its region and \
                country. Nothing wider is ever implied.
                """)
                Text(
                    """
                    Averages over places count each place once; patterns over time count every \
                    visit.
                    """
                )
                Text(
                    """
                    Anything a stat couldn't use is listed under it, with the reason — no record \
                    is dropped silently.
                    """
                )
                Text("""
                Flights follow the great circle between the airports. Trains, road trips, \
                coaches and ferries are measured along the railways, roads and ferry routes \
                of Natural Earth's map, and city transit stop by stop along its line. Where \
                no route joins the ends — and for hikes, bike tours and cable cars — the leg \
                is a straight line marked approximate, unless you enter the distance or ride \
                a catalogue route.
                """)
            }
        }
        .navigationTitle("How Antipodes counts")
    }
}

/// One source's licence, obligation and the snapshot this database was built from.
struct SourceDetailView: View {
    let source: PlaceDataSource

    var body: some View {
        Form {
            Section("Licence") {
                LabeledContent("Licence", value: source.licence)
                if let licenceURL = source.licenceURL, let url = URL(string: licenceURL) {
                    Link("Read the licence", destination: url)
                }
                if let url = URL(string: source.url) {
                    Link(source.name, destination: url)
                }
            }
            if let attribution = source.attribution {
                Section {
                    Text(attribution)
                } header: {
                    Text("Required credit")
                } footer: {
                    Text("This licence requires the credit above wherever the data is used.")
                }
            }
            Section("Used for") {
                Text(source.usedFor)
            }
            if source.sha256 != nil || source.retrieved != nil {
                Section("This build") {
                    if let retrieved = source.retrieved {
                        LabeledContent("Retrieved", value: retrieved)
                    }
                    if let digest = source.sha256 {
                        LabeledContent("Digest", value: String(digest.prefix(16)))
                            .font(.caption.monospaced())
                    }
                }
            }
        }
        .navigationTitle(source.name)
    }
}

/// Settings in their own window on the Mac (⌘,), as Mac apps keep them.
public struct SettingsWindow: View {
    @State private var borderStore = GlobeBorderStore()

    public init() {}

    public var body: some View {
        // SettingsScreen brings its own navigation stack.
        SettingsScreen(isDestination: true)
            .overlay(alignment: .bottom) {
                // Its own window, so the main window's toast is not here to show what a
                // restore or an import added.
                UndoToast()
                    .padding(.bottom, 16)
            }
            .environment(borderStore)
            .frame(minWidth: 520, idealWidth: 560, minHeight: 560, idealHeight: 680)
        #if os(macOS)
            .formStyle(.grouped)
        #endif
    }
}
