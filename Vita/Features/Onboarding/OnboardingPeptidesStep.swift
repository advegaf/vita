import SwiftUI
import SwiftData

// MARK: - Peptides (inline catalog + the existing add sheet)

struct OnboardingPeptidesView: View {
    @Bindable var model: OnboardingModel
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ProtocolItem.sortIndex)]) private var items: [ProtocolItem]
    @State private var searching = false

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                ScreenHeader(eyebrow: "Step 2", title: "Add what you're taking.")
                Text("Or skip and we'll suggest a starter set from your goals.")
                    .font(.system(size: 15)).foregroundStyle(VT.body).padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, VT.sSection).padding(.top, 8).padding(.bottom, 4)

            // Path lives on the model so the wizard chevron pops an open detail
            // (the pushed detail hides the system back: one back button, layered).
            NavigationStack(path: $model.peptidesPath) {
                CatalogBrowseView(showsNavigationTitle: false,
                                  onSearchFocusChanged: { searching = $0 })
                    .navigationDestination(for: String.self) { slug in
                        CompoundDetailLoader(slug: slug)
                            .navigationBarBackButtonHidden(true)
                    }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                // Out of the way while the search keyboard is up (same pattern as
                // the Health step hiding Continue while editing).
                if !searching {
                    continueBar.transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: searching)
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
                #if DEBUG
                // Screenshot hook: VITA_ONB_PICKED=<slug> simulates a user pick at
                // Step 2 (aiGenerated stays false) to exercise the suggestion path.
                if let slug = ProcessInfo.processInfo.environment["VITA_ONB_PICKED"] {
                    let svc = StackService(context: context)
                    if svc.items().isEmpty,
                       let c = ((try? context.fetch(FetchDescriptor<CatalogCompound>())) ?? [])
                           .first(where: { $0.slug == slug }) {
                        svc.commit(svc.draft(for: c))
                    }
                }
                #endif
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

    /// Commit a rule-based starter immediately when the stack is empty (so Review
    /// appears without waiting on the network), then ALWAYS refine with Claude in
    /// the background. The user's own items (`aiGenerated == false` — Step-2 picks
    /// and anything edited/added by hand) are grounding for Claude and suggestion
    /// targets, never edited; the AI freely manages only its own items.
    private func build() async {
        let svc = StackService(context: context)
        let goals = Array(model.selectedGoals)
        let all = (try? context.fetch(FetchDescriptor<CatalogCompound>())) ?? []
        let summaries = all.map { c in
            CatalogSummary(slug: c.slug, name: c.name, categoryRaw: c.categoryRaw,
                           rxStatusRaw: c.rxStatusRaw, doseUnitRaw: c.doseUnitRaw,
                           typicalDoseLow: c.typicalDoseLow, typicalDoseHigh: c.typicalDoseHigh,
                           route: c.primaryRoute?.label, defaultScheduleTypeRaw: c.defaultScheduleTypeRaw)
        }

        // 1) Instant rule-based starter (AI-owned) when the user picked nothing.
        if svc.items().isEmpty {
            for slug in StarterSuggester.slugs(for: goals) {
                guard let c = all.first(where: { $0.slug == slug }) else { continue }
                var d = svc.draft(for: c)
                d.aiGenerated = true
                svc.commit(d)
            }
            model.builtOffline = true
        }

        // 2) Refine with Claude in the background — every run, picks or not.
        let pickedSlugs = svc.items().filter { !$0.aiGenerated }.map(\.compoundSlug)
        let fingerprint = StackService.fingerprint(svc.items())
        let profile = CatalogStore.fetchOrCreateProfile(context, settings: CatalogStore.fetchOrCreateSettings(context))
        // A panel scanned at the Labs step (one step back) must shape the plan:
        // its out-of-range markers join the grounding block.
        let labsLine = LabGrounding.summaryLine(panels: LabService(context: context).panels())
        let input = ProtocolInput(
            goals: goals, pickedSlugs: pickedSlugs, catalog: summaries,
            profile: profileInput(profile), health: model.healthSnapshot,
            labsLine: labsLine)
        model.refineTask?.cancel()   // a re-entered Generating step never overlaps refines
        model.refining = true
        model.refineSuggestions = [:]
        model.refineTask = Task { @MainActor in
            // A cancelled run (the user tapped "Refining with AI…" to skip, or a
            // newer refine replaced this one) must not clobber the current state.
            defer {
                if !Task.isCancelled { model.refining = false; model.refineTask = nil }
            }
            let claude = ClaudeServiceFactory.make()
            do {
                var dto = try await claude.generateProtocol(input)
                var drafts = ClaudeService.buildDrafts(from: dto, catalog: summaries)
                if drafts.isEmpty {
                    dto = try await claude.generateProtocol(input)        // one repair-retry
                    drafts = ClaudeService.buildDrafts(from: dto, catalog: summaries)
                }
                guard !drafts.isEmpty, !Task.isCancelled else { return }  // keep what's there
                let s = StackService(context: context)
                // Anything the user changed while Claude was thinking wins outright
                // (dose edits too, not just adds/removes — hence the fingerprint).
                guard StackService.fingerprint(s.items()) == fingerprint else { return }
                drafts = drafts.map { var d = $0; d.aiGenerated = true; return d }
                // Claude's take on a user-owned compound becomes a tappable
                // suggestion on its Review row, never an applied change.
                var suggestions: [UUID: DoseDraft] = [:]
                for item in s.items() where !item.aiGenerated {
                    guard let d = drafts.first(where: { $0.compoundSlug == item.compoundSlug }),
                          StackService.suggestsChange(dose: item.doseAmount,
                                                      unitRaw: item.doseUnitRaw,
                                                      frequencyRaw: item.schedule?.frequencyRaw ?? "",
                                                      times: item.schedule?.timeSlotsMinutes ?? [],
                                                      draft: d) else { continue }
                    suggestions[item.id] = d
                }
                // In-place merge of the AI-owned items only: ids stay stable while
                // Review renders, one notification/widget rebuild.
                s.applyPlan(drafts, protecting: { !$0.aiGenerated })
                model.refineSuggestions = suggestions
                model.builtOffline = false
                model.refinedByAI = true
            } catch { /* keep what's there + any "Built offline" note */ }
        }
    }

    private func profileInput(_ p: UserProfile) -> ProfileInput {
        var age: Int?
        if let dob = p.birthDate {
            age = Calendar.current.dateComponents([.year], from: dob, to: Date()).year
        }
        return ProfileInput(ageYears: age, biologicalSex: p.biologicalSexRaw, weightKg: p.weightKg)
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
    @State private var suggestedNote: String?

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
                        // The refining state lives in the charcoal pill below.
                        if model.refinedByAI {
                            Text("Refined with AI.")
                                .font(.system(size: 13)).foregroundStyle(VT.dose).padding(.top, 2)
                        } else if model.builtOffline, !model.refining {
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
                            VStack(alignment: .leading, spacing: 4) {
                                Button {
                                    suggestedNote = nil
                                    editDraft = StackService(context: context).draft(for: item)
                                } label: {
                                    StackRow(item: item, compound: bySlug[item.compoundSlug])
                                }
                                .buttonStyle(.plain)
                                // contextMenu, NOT swipeActions: swipe actions are
                                // List-row-only and silently dead inside a ScrollView,
                                // which made Review's items unremovable.
                                .contextMenu {
                                    Button(role: .destructive) {
                                        StackService(context: context).remove(item)
                                    } label: { Label("Remove", systemImage: "trash") }
                                }

                                // Claude's alternative for a compound YOU configured:
                                // surfaced, never applied. Tap to review it in the sheet.
                                if let s = model.refineSuggestions[item.id] {
                                    Button {
                                        var d = StackService(context: context).draft(for: item)
                                        d.doseUnit = s.doseUnit
                                        d.doseAmount = s.doseAmount
                                        d.frequency = s.frequency
                                        d.weekdays = s.weekdays
                                        d.times = s.times
                                        suggestedNote = "vita suggests this for your goals."
                                        editDraft = d
                                    } label: {
                                        Text("vita suggests \(vtFormatNumber(s.doseAmount)) \(s.doseUnit.label), \(s.frequency.label) →")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(VT.dose)
                                    }
                                    .buttonStyle(.plain)
                                    .padding(.leading, 4)
                                }
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

            // While Claude refines, the pill says so; tapping skips the wait
            // (cancels the refine, keeps the starter plan) and proceeds.
            CharcoalPillButton(title: model.refining ? "Refining with AI…" : "Start tracking",
                               loading: model.refining) {
                if model.refining {
                    model.refineTask?.cancel()
                    model.refineTask = nil
                    model.refining = false
                }
                model.advance()
            }
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
        .sheet(item: $editDraft, onDismiss: { suggestedNote = nil }) { d in
            DoseSetupSheet(draft: d, aiSuggestedNote: suggestedNote, onCommit: {
                // Saving (suggested or hand-edited) settles the question for
                // that item; its suggestion line goes away.
                if let id = d.editingItemID { model.refineSuggestions.removeValue(forKey: id) }
            })
        }
    }
}
