import SwiftUI

/// Swipeable pages: the system's paging `TabView` on iPhone and iPad; on the Mac, which
/// has no paging style, one page at a time with arrows, page dots and the arrow keys.
struct Pager<Page: View>: View {
    @Binding var page: Int
    let count: Int
    @ViewBuilder let content: (Int) -> Page

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        #if os(iOS)
            TabView(selection: $page) {
                ForEach(0 ..< count, id: \.self) { index in
                    content(index).tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        #else
            VStack(spacing: 12) {
                content(page)
                    .id(page)
                    .transition(reduceMotion ? .opacity : .push(from: .trailing))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                HStack(spacing: 18) {
                    Button("Previous", systemImage: "chevron.left") { go(-1) }
                        .disabled(page == 0)
                    PageDots(count: count, page: page)
                    Button("Next", systemImage: "chevron.right") { go(1) }
                        .disabled(page >= count - 1)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.glass)
                .padding(.bottom, 8)
            }
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(.leftArrow) {
                go(-1)
                return .handled
            }
            .onKeyPress(.rightArrow) {
                go(1)
                return .handled
            }
        #endif
    }

    private func go(_ step: Int) {
        let next = min(max(0, page + step), count - 1)
        guard next != page else { return }
        withAnimation(reduceMotion ? nil : .snappy) { page = next }
    }
}

/// Which page of how many, as dots.
private struct PageDots: View {
    let count: Int
    let page: Int

    var body: some View {
        HStack(spacing: 7) {
            ForEach(0 ..< count, id: \.self) { index in
                Circle()
                    .fill(index == page ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Page \(page + 1) of \(count)")
    }
}
