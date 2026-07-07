import SwiftUI
import SwiftData

struct CatalogBrowseView: View {
    /// When false (e.g. inside onboarding, where the step already has a big
    /// headline), the redundant "Catalog" nav title is dropped.
    var showsNavigationTitle: Bool = true
    /// Lets a host react to the search keyboard (onboarding hides its Continue
    /// bar while searching). Same defaulted-callback convention as `onSaved`.
    var onSearchFocusChanged: (Bool) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Query(sort: \CatalogCompound.name) private var compounds: [CatalogCompound]
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        ZStack {
            // Full-screen cream, exactly like Chat: the keyboard's rounded bevels
            // reveal canvas, never the white system background.
            VT.canvas.ignoresSafeArea()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: VT.sSection) {
                    searchField
                    if grouped.isEmpty {
                        noResults
                    } else {
                        ForEach(grouped, id: \.0) { cat, items in
                            section(cat, items)
                        }
                    }
                }
                .padding(VT.sSection)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
        }
        .onChange(of: searchFocused) { _, focused in onSearchFocusChanged(focused) }
        #if DEBUG
        // Screenshot hook: VITA_CATALOG_FOCUS=1 raises the search keyboard.
        .task {
            if ProcessInfo.processInfo.environment["VITA_CATALOG_FOCUS"] == "1" {
                try? await Task.sleep(nanoseconds: 600_000_000)
                searchFocused = true
            }
        }
        #endif
        .navigationTitle(showsNavigationTitle ? "Catalog" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(showsNavigationTitle ? .automatic : .hidden, for: .navigationBar)
    }

    // MARK: Search

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(VT.micro)
            TextField("Search peptides", text: $search)
                .foregroundStyle(VT.ink)
                .autocorrectionDisabled()
                .focused($searchFocused)
            if !search.isEmpty {
                Button { search = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(VT.micro)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(VT.card, in: Capsule())
        .overlay(Capsule().stroke(VT.hairline, lineWidth: 1))
    }

    // MARK: Sections

    private func section(_ cat: PeptideCategory, _ items: [CatalogCompound]) -> some View {
        VStack(alignment: .leading, spacing: VT.sCardGap) {
            Text(cat.title.uppercased())
                .font(.system(size: 12, weight: .semibold)).tracking(0.4)
                .foregroundStyle(VT.micro)
            VStack(spacing: 0) {
                ForEach(items) { c in
                    CatalogRowView(compound: c)
                    if c.slug != items.last?.slug {
                        Rectangle().fill(VT.hairline).frame(height: 1).padding(.leading, 72)
                    }
                }
            }
            .vtCard()
        }
    }

    private var noResults: some View {
        VStack(spacing: 6) {
            Text("No matches.").font(.vtHeadline).foregroundStyle(VT.ink)
            Text("Try a different name, or browse by category.")
                .font(.system(size: 15)).foregroundStyle(VT.body)
        }
        .frame(maxWidth: .infinity).padding(.top, 48)
    }

    private var grouped: [(PeptideCategory, [CatalogCompound])] {
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = q.isEmpty ? compounds : compounds.filter { c in
            c.name.lowercased().contains(q)
            || c.aliases.contains { $0.lowercased().contains(q) }
            || c.category.title.lowercased().contains(q)
        }
        let dict = Dictionary(grouping: filtered, by: { $0.category })
        return dict.keys.sorted { $0.order < $1.order }
            .map { ($0, (dict[$0] ?? []).sorted { $0.name < $1.name }) }
    }
}

// MARK: - Catalog row

struct CatalogRowView: View {
    let compound: CatalogCompound
    @Environment(\.modelContext) private var context
    @State private var inStack = false
    @State private var setupDraft: DoseDraft?

    var body: some View {
        HStack(spacing: 12) {
            NavigationLink(value: compound.slug) {
                HStack(spacing: 12) {
                    CompoundTile(category: compound.category)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(compound.name)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(VT.ink)
                            .lineLimit(2)   // wrap; no .fixedSize (would widen the row → h-scroll)
                        if !compound.subtitle.isEmpty {
                            Text(compound.subtitle)
                                .font(.system(size: 13)).foregroundStyle(VT.body)
                                .lineLimit(2)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(compound.subtitle.isEmpty ? compound.name : "\(compound.name), \(compound.subtitle)")
            }
            .buttonStyle(.plain)

            if compound.rxStatus == .rx {
                RxBadge()
            }
            AddKnob(inStack: inStack) {
                guard !inStack else { return }
                setupDraft = StackService(context: context).draft(for: compound)
                Haptics.press()
            }
        }
        .sheet(item: $setupDraft) { d in
            DoseSetupSheet(draft: d, rangeText: compound.doseRangeText, about: compound.about) {
                inStack = StackService(context: context).isInStack(compound.slug)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .onAppear { inStack = StackService(context: context).isInStack(compound.slug) }
    }
}

/// "Add to stack" — a deliberately lighter cousin of the pin-tap (brown fill,
/// smaller bump, soft impact only; the stroke-draw + success haptic stay exclusive
/// to dose-logging).
private struct AddKnob: View {
    let inStack: Bool
    let action: () -> Void
    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle().stroke(VT.body.opacity(0.4), lineWidth: 2).opacity(inStack ? 0 : 1)
                Circle().fill(VT.why).opacity(inStack ? 1 : 0)
                Image(systemName: inStack ? "checkmark" : "plus")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(inStack ? .white : VT.body)
            }
            .frame(width: 30, height: 30)
            .scaleEffect(pressed ? 0.9 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !inStack { pressed = true } }
                .onEnded { _ in pressed = false }
        )
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: pressed)
        .accessibilityLabel(inStack ? "In stack" : "Add to stack")
    }
}
