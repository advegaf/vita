import SwiftUI
import SwiftData

// MARK: - Peptides (inline catalog + the existing add sheet)

struct OnboardingPeptidesView: View {
    @Bindable var model: OnboardingModel
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ProtocolItem.sortIndex)]) private var items: [ProtocolItem]

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ScreenHeader(eyebrow: "Step 2", title: "Add what you're taking.")
                Text("Or skip and we'll suggest a starter set from your goals.")
                    .font(.system(size: 15)).foregroundStyle(VT.body).padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VT.sSection).padding(.top, 8).padding(.bottom, 4)

            NavigationStack {
                CatalogBrowseView(showsNavigationTitle: false)
                    .navigationDestination(for: String.self) { slug in
                        CompoundDetailLoader(slug: slug)
                    }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { continueBar }
        }
    }

    /// The Continue pill floats over the catalog: rows fade out under a soft
    /// cream gradient instead of resting on a hard cream band ("tab bar" look).
    private var continueBar: some View {
        CharcoalPillButton(title: items.isEmpty ? "Continue" : "Continue with \(items.count)",
                           action: model.advance)
            .padding(.horizontal, VT.sSection)
            .padding(.top, 16).padding(.bottom, 8)
            .frame(maxWidth: .infinity)
            .background(
                LinearGradient(colors: [VT.canvas.opacity(0), VT.canvas],
                               startPoint: .top, endPoint: .bottom)
            )
    }
}

/// Resolves a slug to its compound for the pushed detail (inside the wizard's catalog).
struct CompoundDetailLoader: View {
    let slug: String
    @Query private var compounds: [CatalogCompound]
    var body: some View {
        if let c = compounds.first(where: { $0.slug == slug }) {
            CompoundDetailView(compound: c)
        }
    }
}

// MARK: - Generating (rule-based stub; real AI is M3)

struct GeneratingView: View {
    @Bindable var model: OnboardingModel
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: VT.sSection) {
            Spacer()
            ThinkingDots(reduceMotion: reduceMotion, label: "Building your plan")
            Text("Building your plan…")
                .font(VFont.display(22, weight: .bold, relativeTo: .title2)).foregroundStyle(VT.ink)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            Task {
                async let minDwell: Void = dwell()
                await build()
                _ = await minDwell
                model.advance()
            }
        }
    }

    private func dwell() async {
        let seconds: Double = reduceMotion ? 0.4 : 1.4
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    /// Real protocol generation. If the user already picked peptides, leave the
    /// stack alone. Otherwise ask Claude for a grounded starter; on any failure
    /// (no key / network / valid output) fall back to the rule-based starter.
    private func build() async {
        let svc = StackService(context: context)
        guard svc.items().isEmpty else { return }   // user already picked peptides

        let goals = Array(model.selectedGoals)
        let all = (try? context.fetch(FetchDescriptor<CatalogCompound>())) ?? []
        let summaries = all.map { c in
            CatalogSummary(slug: c.slug, name: c.name, categoryRaw: c.categoryRaw,
                           rxStatusRaw: c.rxStatusRaw, doseUnitRaw: c.doseUnitRaw,
                           typicalDoseLow: c.typicalDoseLow, typicalDoseHigh: c.typicalDoseHigh,
                           route: c.primaryRoute?.label, defaultScheduleTypeRaw: c.defaultScheduleTypeRaw)
        }
        let settings = CatalogStore.fetchOrCreateSettings(context)
        let profile = CatalogStore.fetchOrCreateProfile(context, settings: settings)
        let input = ProtocolInput(
            goals: goals, pickedSlugs: svc.items().map(\.compoundSlug),
            catalog: summaries, profile: profileInput(profile), health: model.healthSnapshot)

        let claude = ClaudeServiceFactory.make()
        do {
            var dto = try await claude.generateProtocol(input)
            var drafts = ClaudeService.buildDrafts(from: dto, catalog: summaries)
            if drafts.isEmpty {
                dto = try await claude.generateProtocol(input)            // one repair-retry
                drafts = ClaudeService.buildDrafts(from: dto, catalog: summaries)
            }
            guard !drafts.isEmpty else { fallback(svc, goals, summaries); return }
            for d in drafts { svc.commit(d) }
        } catch {
            fallback(svc, goals, summaries)
        }
    }

    private func profileInput(_ p: UserProfile) -> ProfileInput {
        var age: Int?
        if let dob = p.birthDate {
            age = Calendar.current.dateComponents([.year], from: dob, to: Date()).year
        }
        return ProfileInput(ageYears: age, biologicalSex: p.biologicalSexRaw, weightKg: p.weightKg)
    }

    /// Rule-based starter (the M2 stub), used whenever live generation fails.
    private func fallback(_ svc: StackService, _ goals: [GoalKind], _ summaries: [CatalogSummary]) {
        model.builtOffline = true
        let all = (try? context.fetch(FetchDescriptor<CatalogCompound>())) ?? []
        for slug in StarterSuggester.slugs(for: goals) {
            guard let c = all.first(where: { $0.slug == slug }) else { continue }
            svc.commit(svc.draft(for: c))
        }
    }
}

// MARK: - Review (editable stack)

struct ReviewView: View {
    @Bindable var model: OnboardingModel
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ProtocolItem.sortIndex), SortDescriptor(\ProtocolItem.addedAt)])
    private var items: [ProtocolItem]
    @Query private var compounds: [CatalogCompound]
    @State private var showCatalog = false
    @State private var editDraft: DoseDraft?

    private var bySlug: [String: CatalogCompound] {
        Dictionary(compounds.map { ($0.slug, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: VT.sCardGap) {
                    VStack(alignment: .leading, spacing: 4) {
                        ScreenHeader(eyebrow: "Review",
                                     title: items.isEmpty ? "Your plan." : "Your plan: \(items.count).")
                        Text("Tap to adjust. Everything is editable later, too.")
                            .font(.system(size: 15)).foregroundStyle(VT.body).padding(.top, 2)
                        if model.builtOffline {
                            Text("Built offline. Tap any item to refine it.")
                                .font(.system(size: 13)).foregroundStyle(VT.micro).padding(.top, 2)
                        }
                    }
                    .padding(.top, 8)

                    if items.isEmpty {
                        Text("Nothing here yet. Add a peptide to get started.")
                            .font(.system(size: 15)).foregroundStyle(VT.body)
                            .frame(maxWidth: .infinity).padding(.top, 24)
                    } else {
                        ForEach(items) { item in
                            Button {
                                editDraft = StackService(context: context).draft(for: item)
                            } label: {
                                StackRow(item: item, compound: bySlug[item.compoundSlug])
                            }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) {
                                    StackService(context: context).remove(item)
                                } label: { Label("Remove", systemImage: "trash") }
                            }
                        }
                    }

                    Button { showCatalog = true } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus.circle")
                            Text("Add more")
                        }
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.dose)
                    }
                    .buttonStyle(.plain).padding(.top, 4)
                }
                .padding(VT.sSection)
            }
            .scrollIndicators(.hidden)

            CharcoalPillButton(title: "Start tracking", action: model.advance)
                .padding(.horizontal, VT.sSection).padding(.bottom, 8)
        }
        .sheet(isPresented: $showCatalog) {
            NavigationStack {
                CatalogBrowseView(showsNavigationTitle: false)
                    .navigationDestination(for: String.self) { slug in
                        CompoundDetailLoader(slug: slug)
                    }
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { showCatalog = false }.foregroundStyle(VT.ink)
                        }
                    }
            }
        }
        .sheet(item: $editDraft) { d in
            DoseSetupSheet(draft: d)
        }
    }
}
