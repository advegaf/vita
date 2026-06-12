import SwiftUI

/// Live "in 3h 20m" countdown, ticking each second, tabular.
struct CountdownText: View {
    let target: Date
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(Self.format(target.timeIntervalSince(ctx.date)))
        }
    }
    static func format(_ s: TimeInterval) -> String {
        if s <= 0 { return "now" }
        let total = Int(s)
        let h = total / 3600, m = (total % 3600) / 60
        if h > 0 { return "in \(h)h \(m)m" }
        if m > 0 { return "in \(m)m \(total % 60)s" }
        return "in \(total)s"
    }
}

/// Quiet dot-meter — celebration without a scoreboard. Never a progress ring.
struct DotMeter: View {
    var filled: Int
    var total: Int
    var note: String? = nil      // e.g. "3-day streak." appended after the count
    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                ForEach(0..<max(total, 0), id: \.self) { i in
                    Circle()
                        .fill(i < filled ? VT.why : VT.ink.opacity(0.12))
                        .frame(width: 7, height: 7)
                }
            }
            Text(note.map { "\(filled) of \(total) logged · \($0)" } ?? "\(filled) of \(total) logged")
                .font(.system(size: 13, weight: .medium)).vtTabular()
                .foregroundStyle(VT.micro)
        }
    }
}

/// Calm pulsing 3-dot indicator. Shared by chat ("vita is thinking") and the
/// onboarding generating screen. Reduce-Motion: static dots.
struct ThinkingDots: View {
    var reduceMotion: Bool = false
    var label: String = "Loading"
    @State private var phase = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle().fill(VT.micro)
                    .frame(width: 7, height: 7)
                    .opacity(phase == i ? 1 : 0.3)
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.45).repeatForever()) { phase = 2 }
            Task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    await MainActor.run { phase = (phase + 1) % 3 }
                }
            }
        }
        .accessibilityLabel(label)
    }
}

/// The wordmark with the app icon's signature: "Vita" plus the period drawn as
/// the candy-cyan dot, seated on the text baseline. Homepage and home-screen
/// icon speak the same sentence.
struct VitaWordmark: View {
    var size: CGFloat = 17
    var weight: Font.Weight = .bold
    var relativeTo: Font.TextStyle = .headline
    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: size * 0.12) {
            Text("Vita").font(VFont.display(size, weight: weight, relativeTo: relativeTo))
                .foregroundStyle(VT.ink)
            Circle().fill(VT.dose)
                .frame(width: size * 0.26, height: size * 0.26)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Vita")
    }
}

/// Top bar: translucent "Vita." wordmark pill (left) + "..." overflow (right).
struct TopBarPill: View {
    var onMenu: () -> Void = {}
    var body: some View {
        HStack {
            VitaWordmark()
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(.regularMaterial, in: Capsule())

            Spacer()

            Button(action: onMenu) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(VT.ink)
                    .frame(width: 38, height: 38)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
        }
    }
}

#Preview {
    VStack(spacing: 28) {
        TopBarPill()
        DotMeter(filled: 3, total: 4)
        CountdownText(target: Date().addingTimeInterval(3 * 3600 + 1200))
            .font(.system(size: 15, weight: .semibold))
    }
    .padding(24)
    .background(VT.canvas)
}
