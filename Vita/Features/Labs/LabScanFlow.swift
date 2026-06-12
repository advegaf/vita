import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// The lab-scan sheet: one-time consent → pick a source (camera / Photos / PDF) →
/// "Reading your labs…" → review. The picked Data is EXIF-stripped before it is
/// sent to Claude AND before it's stored. Educational, not medical advice.
struct LabScanFlow: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    /// After a save, offer "Ask vita to review your plan →" (prefills chat, never
    /// auto-sends). Onboarding passes false — chat isn't reachable mid-wizard.
    var offersChatReview = true
    var onSaved: () -> Void = {}

    @State private var phase: Phase = .intro
    @State private var photoItem: PhotosPickerItem?
    @State private var showCamera = false
    @State private var showFiles = false
    @State private var prepared: (data: Data, mediaType: String)?
    @State private var dto: LabPanelDTO?
    @State private var errorText: String?
    @State private var readingHint: String?
    @State private var diagText: String?
    @State private var interpretTask: Task<Void, Never>?

    private enum Phase { case intro, reading, review, saved, failed }

    var body: some View {
        NavigationStack {
            content
                .background(VT.canvas)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }.foregroundStyle(VT.ink)
                    }
                }
        }
        .sheet(isPresented: $showCamera) {
            CameraPicker { data in handle(data, hint: "image/jpeg") }
                .ignoresSafeArea()
        }
        .fileImporter(isPresented: $showFiles, allowedContentTypes: [.pdf]) { result in
            if case let .success(url) = result { importPDF(url) }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await MainActor.run { handle(data, hint: nil) }
                }
            }
        }
        // Closing or swiping the sheet away mustn't leak the in-flight request.
        .onDisappear { interpretTask?.cancel() }
    }

    @ViewBuilder private var content: some View {
        switch phase {
        case .intro:
            ScrollView { intro.padding(VT.sSection) }.scrollIndicators(.hidden)
        case .reading:
            reading
        case .review:
            if let dto {
                LabReviewView(dto: dto, scan: prepared) {
                    onSaved()
                    if offersChatReview { phase = .saved } else { dismiss() }
                }
            }
        case .saved:
            savedView
        case .failed:
            failed
        }
    }

    /// Post-save: the panel is in; offer a one-tap plan review in chat. The tap
    /// PREFILLS the chat input (the user still sends it) — same consent posture
    /// as the marker chart's "Ask vita about this".
    private var savedView: some View {
        VStack(spacing: VT.sCardGap) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 30)).foregroundStyle(VT.why)
            Text("Panel saved.")
                .font(VFont.display(20, weight: .bold, relativeTo: .title3)).foregroundStyle(VT.ink)
            Text("Your results now ground vita's answers and plan suggestions.")
                .font(.system(size: 14)).foregroundStyle(VT.micro)
                .multilineTextAlignment(.center)
            Button {
                NotificationRouter.shared.pendingChatPrompt =
                    LabGrounding.stackReviewPrompt(panels: LabService(context: context).panels())
                NotificationRouter.shared.pendingTab = .chat
                dismiss()
            } label: {
                Text("Ask vita to review your plan →")
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.dose)
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
            Button("Done") { dismiss() }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.micro)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(VT.sSection)
    }

    // MARK: Intro (consent folded in for the first scan)

    private var intro: some View {
        VStack(alignment: .leading, spacing: VT.sSection) {
            ScreenHeader(eyebrow: "Labs", title: "Scan your bloodwork.")
            VStack(alignment: .leading, spacing: VT.sCardGap) {
                if CameraPicker.isAvailable {
                    sourceRow("camera.fill", "Take a photo") { showCamera = true }
                }
                photoRow
                sourceRow("doc.fill", "Import a PDF") { showFiles = true }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VT.sCardPad).vtCard()

            VStack(alignment: .leading, spacing: 6) {
                vtLead("How it works.", color: VT.dose)
                Text("Vita sends the image to Anthropic's Claude to read the values, then shows them for you to check before saving. The original stays on your phone.")
                    .font(.system(size: 14)).foregroundStyle(VT.body).lineSpacing(2)
                Text("Educational, not medical advice. Discuss results with your clinician.")
                    .font(.system(size: 12)).foregroundStyle(VT.micro)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VT.sCardPad).vtCard()
        }
    }

    private func sourceRow(_ symbol: String, _ title: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 18)).foregroundStyle(VT.dose).frame(width: 28)
                Text(title).font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.micro)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var photoRow: some View {
        PhotosPicker(selection: $photoItem, matching: .images) {
            HStack(spacing: 12) {
                Image(systemName: "photo.fill").font(.system(size: 18)).foregroundStyle(VT.dose).frame(width: 28)
                Text("Choose from Photos").font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.ink)
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.micro)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var reading: some View {
        VStack(spacing: VT.sCardGap) {
            ThinkingDots(label: "Reading your labs")
            Text("Reading your labs…")
                .font(VFont.display(20, weight: .bold, relativeTo: .title3)).foregroundStyle(VT.ink)
            if let readingHint {
                Text(readingHint)
                    .font(.system(size: 14)).foregroundStyle(VT.micro)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(VT.sSection)
    }

    private var failed: some View {
        VStack(spacing: VT.sCardGap) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 26)).foregroundStyle(VT.overdue)
            Text(errorText ?? "Couldn't read that clearly.")
                .font(.system(size: 16)).foregroundStyle(VT.body).multilineTextAlignment(.center)
            #if DEBUG
            if let diagText {
                Text(diagText).font(.system(size: 11)).foregroundStyle(VT.micro)
                    .multilineTextAlignment(.center).padding(.horizontal)
            }
            #endif
            VStack(spacing: 10) {
                if prepared != nil {
                    CharcoalPillButton(title: "Retry") {
                        if let p = prepared { errorText = nil; runInterpret(p) }
                    }
                    .frame(maxWidth: 240)
                }
                Button("Try another file") { phase = .intro; errorText = nil; prepared = nil }
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.dose)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(VT.sSection)
    }

    // MARK: Handling

    private func importPDF(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return }
        handle(data, hint: "application/pdf")
    }

    private func handle(_ data: Data, hint: String?) {
        // One-time consent recorded the first time a scan is actually sent.
        let settings = CatalogStore.fetchOrCreateSettings(context)
        if settings.labConsentedAt == nil { settings.labConsentedAt = Date(); try? context.save() }

        let prep = LabImageEncoder.prepare(data: data, mediaTypeHint: hint)
        // A PDF PDFKit can't even open has no readable pages: fail fast and
        // specifically, without burning an API call on it.
        if prep.mediaType == "application/pdf", LabImageEncoder.pdfPageCount(prep.data) == 0 {
            errorText = "That PDF looks damaged. Try exporting it again, or use a photo."
            prepared = nil
            photoItem = nil
            phase = .failed
            return
        }
        prepared = prep
        readingHint = Self.readingHint(for: prep)
        photoItem = nil
        runInterpret(prep)
    }

    /// An honest expectation-setter under the spinner — a multi-page report is slow to read.
    static func readingHint(for prep: (data: Data, mediaType: String)) -> String {
        if prep.mediaType == "application/pdf" {
            let n = LabImageEncoder.pdfPageCount(prep.data)
            if n > 2 { return "Reading \(n) pages. A long report can take up to a minute." }
        }
        return "This can take a moment."
    }

    private func runInterpret(_ prep: (data: Data, mediaType: String)) {
        phase = .reading
        diagText = nil
        interpretTask = Task {
            let start = Date()
            do {
                let result = try await LabService(context: context).interpret(imageData: prep.data, mediaType: prep.mediaType)
                if Task.isCancelled { return }
                await MainActor.run {
                    if result.values.isEmpty {
                        errorText = "No values found on that page. Try a clearer photo or a single-page export."
                        setDiag(prep, "values: 0", start); phase = .failed
                    } else {
                        dto = result; phase = .review
                    }
                }
            } catch {
                if Task.isCancelled { return }
                await MainActor.run {
                    errorText = Self.labErrorMessage(error)
                    setDiag(prep, "error: \(error)", start); phase = .failed
                }
            }
        }
    }

    private func setDiag(_ prep: (data: Data, mediaType: String), _ outcome: String, _ start: Date) {
        #if DEBUG
        let pdf = prep.mediaType == "application/pdf"
        diagText = "pdf=\(pdf) pages=\(pdf ? LabImageEncoder.pdfPageCount(prep.data) : 0)"
            + " text=\(pdf ? LabImageEncoder.pdfHasTextLayer(prep.data) : false)"
            + " · \(outcome) · \(Int(Date().timeIntervalSince(start)))s"
        #endif
    }

    /// Maps a thrown error to a calm, specific line (offline / busy / too-large / etc.).
    static func labErrorMessage(_ error: Error) -> String {
        guard let e = error as? AnthropicClient.AnthropicError else {
            return "Couldn't read that clearly. Try a sharper, well-lit photo or a PDF."
        }
        switch e {
        case .noKey:      return "No API key found. Add your Anthropic key in Settings to read labs."
        case .transport:  return "You're offline. Reconnect and try again."
        case .overloaded: return "The reader is busy right now. Give it a moment and retry."
        case .http(let code, let body):
            if body.lowercased().contains("credit") {
                return "Your Anthropic account is out of credits. Add credits at console.anthropic.com, then retry."
            }
            return "Couldn't read that file (error \(code)). Try a photo or a single-page PDF."
        case .decode, .noToolUse: return "Couldn't make sense of that page. Try a sharper photo or a clearer scan."
        }
    }
}
