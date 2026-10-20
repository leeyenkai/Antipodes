import SwiftUI

/// Shown instead of the app when the travel log cannot be opened.
///
/// The alternative — carrying on with an empty log held in memory — would let the user
/// log a week of travel and lose all of it at the next launch, with nothing to say so.
/// Refusing to start until the store opens is the honest failure.
public struct StoreUnavailableView: View {
    let error: any Error
    let retry: () -> Void

    public init(error: any Error, retry: @escaping () -> Void) {
        self.error = error
        self.retry = retry
    }

    public var body: some View {
        ContentUnavailableView {
            Label("Your log couldn't be opened", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text("""
            Antipodes stopped rather than start with an empty log, so nothing you have \
            already logged is touched. Restarting your device usually clears this. If it \
            keeps happening, make sure there is free storage space and try again.
            """)
            #if DEBUG
                Text(String(describing: error))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            #endif
        } actions: {
            Button("Try Again", action: retry)
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.heroGradient)
        .preferredColorScheme(.dark)
    }
}
