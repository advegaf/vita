#if DEBUG
import SwiftUI

/// M38 architecture spike (launch with VITA_SPIKE_CARD=1) — validates the two
/// load-bearing assumptions behind the card-navigation redesign before any real
/// build:
///  1. `onGeometryChange` on the sheet content streams the sheet's global minY
///     PER FRAME during interactive drags and detent animations (drives the
///     photo parallax/scrim/header chrome).
///  2. Scroll-to-expand handoff between inner scroll content and the sheet.
///     Run 1 finding: with `.presentationBackgroundInteraction(.enabled)` the
///     content scrolls in place and the sheet never moves. VITA_SPIKE_MODAL=1
///     drops background interaction to isolate whether the flag is the gate or
///     whether iOS 26's SwiftUI ScrollView is never sheet-tracked at all.
/// Deleted once ImmersiveRootView lands.
struct SpikeCardView: View {
    @State private var detent: PresentationDetent = .fraction(0.62)
    @State private var presented = true
    @State private var topY: CGFloat = 0
    /// Distinct integer minY values observed — per-frame streaming shows up as
    /// dozens of samples per transition, endpoints-only as ~2.
    @State private var samples: Set<Int> = []
    @State private var tunerNote = "-"

    private var modalVariant: Bool {
        ProcessInfo.processInfo.environment["VITA_SPIKE_MODAL"] == "1"
    }

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [.black, Color(hue: 0.35, saturation: 0.35, brightness: 0.35)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            // Probe readout for the UI test (and for eyeballing in screenshots).
            Text("y=\(Int(topY)) n=\(samples.count) t=\(tunerNote)")
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white)
                .padding(.top, 2)
                .accessibilityIdentifier("spike-probe")
        }
        .sheet(isPresented: $presented) {
            sheetContent
        }
        // Re-present guard: the card must be impossible to lose.
        .onChange(of: presented) { _, shown in if !shown { presented = true } }
    }

    @ViewBuilder private var sheetContent: some View {
        let base = NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    NavigationLink("Push a detail") { pushedDetail }
                        .font(.headline)
                    ForEach(0..<60, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(.quaternary).frame(height: 44)
                            .overlay(Text("Row \(i)"))
                    }
                }
                .padding(20)
            }
            .navigationTitle("Spike")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Expand") { detent = .large }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Rest") { detent = .fraction(0.62) }
                }
            }
        }
        .background(SheetTuner { tunerNote = $0 })
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { y in
            topY = y
            samples.insert(Int(y))
        }
        .presentationDetents([.fraction(0.62), .large], selection: $detent)
        .presentationCornerRadius(36)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled()

        if modalVariant {
            base
        } else {
            base.presentationBackgroundInteraction(.enabled(upThrough: .large))
        }
    }

    private var pushedDetail: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(0..<40, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.tertiary).frame(height: 44)
                        .overlay(Text("Detail \(i)"))
                }
            }
            .padding(20)
        }
        .navigationTitle("Pushed")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview { SpikeCardView() }
#endif
