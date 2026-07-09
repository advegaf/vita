import SwiftUI
import SwiftData

/// Home (image #2). Dynamic count + greeting headline, an "Up next." FocusCard,
/// the expanding Morning/Midday/Night candy control, full-size pins filtered to the
/// selected block, and a DotMeter. M4: logging is persistent (DoseLog), with
/// taken/skip/undo, calm overdue, a streak, day-complete + rest-day moments, and a
/// PRN "as needed" card. State is derived live from the log via ScheduleService.
struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\ProtocolItem.sortIndex), SortDescriptor(\ProtocolItem.addedAt)])
    private var items: [ProtocolItem]
    @Query private var logs: [DoseLog]

    @State private var selectedBlock: String?
    @State private var showSettings = false
    @State private var editDraft: DoseDraft?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var logger: DoseLogger { DoseLogger(context: context) }

    /// Logs an occurrence inside a single animation transaction so the focus-card
    /// swap, DotMeter, and headline count all move together (the pin knob is already
    /// animated). Reduce-motion collapses it to a quick fade.
    private func logAnimated(_ item: ProtocolItem, _ o: DoseOccurrence, status: DoseStatus,
                             site: InjectionSite? = nil) {
        withAnimation(reduceMotion ? VMotion.reduced : VMotion.cardEntrance) {
            logger.log(item: item, occurrence: o, status: status, site: site)
        }
    }

    /// Pin site line: the suggestion before logging, the stamped site after.
    private func siteText(for item: ProtocolItem, occurrence o: DoseOccurrence,
                          state: DoseState, now: Date) -> String? {
        guard item.isInjectable else { return nil }
        if state == .taken {
            let start = Calendar.current.startOfDay(for: now)
            return logs.first {
                DoseLogger.matches($0, itemID: item.id, dayStart: start, minutes: o.minutes)
            }?.site?.label
        }
        return SiteRotation.next(for: item, logs: logs).map { "→ \($0.label)" }
    }
    private func openDetail(_ item: ProtocolItem) {
        NotificationRouter.shared.pendingDetailItemID = item.id
    }
    private var prnItems: [ProtocolItem] { items.filter { ($0.schedule?.frequency ?? .daily) == .prn } }

    /// A single quiet line when any vial is running low (nil otherwise). Taps into Stack.
    private var lowVialLine: String? {
        let low = items.filter { item in
            guard let vial = item.vial else { return false }
            let itemLogs = logs.filter { $0.compoundSlug == item.compoundSlug }
            return VialEngine.status(item: item, vial: vial, logs: itemLogs, asOf: .now).isLow
        }
        guard !low.isEmpty else { return nil }
        if low.count == 1 { return "\(low[0].displayName) vial is running low" }
        return "\(low.count) vials are running low"
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { ctx in
            content(now: ctx.date)
        }
        .onAppear {
            #if DEBUG
            if let b = ProcessInfo.processInfo.environment["VITA_TODAY_BLOCK"] { selectedBlock = b }
            #endif
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $editDraft) { d in DoseSetupSheet(draft: d) }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["VITA_OPEN_SETTINGS"] == "1" {
                try? await Task.sleep(nanoseconds: 400_000_000)
                showSettings = true
            }
            #endif
        }
    }

    private func content(now: Date) -> some View {
        let currentBlock = DayBlock.from(minutes: minutes(of: now))
        let grouped = occurrencesByBlock(on: now)
        let allOcc = grouped.values.flatMap { $0 }
        let total = allOcc.count
        let acted = allOcc.filter { isActed($0, now: now) }.count
        let remaining = total - acted
        let shownBlock = DayBlock(rawValue: selectedBlock.flatMap(blockIndex) ?? currentBlock.rawValue) ?? currentBlock
        let next = nextUnacted(in: allOcc, now: now)
        let streak = StreakService.currentStreak(items: items, logs: logs, asOf: now)
        let restingByBlock = restingItemsByBlock(on: now)
        let hasResting = restingByBlock.values.contains { !$0.isEmpty }

        return ScrollView {
            VStack(alignment: .leading, spacing: VT.sCardGap) {
                TopBarPill(onMenu: { showSettings = true }).padding(.bottom, 4)

                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY")
                        .font(.system(size: 12, weight: .medium)).tracking(0.4)
                        .textCase(.uppercase).foregroundStyle(VT.micro)
                    VStack(alignment: .leading, spacing: 0) {
                        if total > 0 {
                            Text(countLine(remaining: remaining))
                                .contentTransition(.numericText())
                        }
                        Text(currentBlock.greeting)
                    }
                    .vtHeadlineStyle()
                }
                .padding(.bottom, 2)

                if items.isEmpty {
                    emptyStack
                } else {
                    Group {
                        if total == 0 && !hasResting {
                            RestDayCard()
                        } else if total > 0 && remaining == 0 {
                            DayCompleteCard()
                        } else if let next {
                            focusCard(next, now: now)
                        }
                    }
                    // The crescendo: the focus card dissolving into "All done" as the
                    // last dose is logged. Identity swap drives an insert/remove.
                    .id(remaining == 0 ? "complete" : (next?.id ?? "rest"))
                    .transition(reduceMotion ? .opacity
                        : .asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.97, anchor: .top)),
                                      removal: .opacity))

                    if total > 0 || hasResting {
                        CandySegmentedControl(
                            segments: CandySegmentedControl.dayBlockSegments,
                            selection: blockBinding(default: currentBlock)
                        )
                        .padding(.vertical, 2)

                        blockPins(shownBlock, grouped[shownBlock] ?? [],
                                  resting: restingByBlock[shownBlock] ?? [], now: now)

                        if total > 0 {
                            DotMeter(filled: acted, total: total,
                                     note: streak > 0 ? "\(streak)-day streak." : nil)
                                .padding(.top, 6).frame(maxWidth: .infinity)
                        }
                    }

                    if let lowVialLine {
                        Button { NotificationRouter.shared.pendingTab = .protocolTab } label: {
                            HStack(spacing: 4) {
                                Text(lowVialLine)
                                    .font(.system(size: 14, weight: .semibold)).foregroundStyle(VT.body)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(VT.micro)
                            }
                            .frame(maxWidth: .infinity).frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    if !prnItems.isEmpty { asNeededCard(now: now) }
                }
            }
            .padding(VT.sSection)
        }
        .scrollIndicators(.hidden)
        .background(VT.canvas)
    }

    // MARK: Up next FocusCard

    private func focusCard(_ o: DoseOccurrence, now: Date) -> some View {
        let item = items.first { $0.id == o.itemID }
        return FocusCard(
            peptide: item?.displayName ?? "",
            doseLine: doseLine(item, now: now),
            due: dateFor(minutes: o.minutes),
            siteLine: item.flatMap { i in
                i.isInjectable ? SiteRotation.next(for: i, logs: logs).map { "→ \($0.label)" } : nil
            },
            onLog: { if let item { logAnimated(item, o, status: .taken) } },
            onOpenDetail: { if let item { openDetail(item) } }
        )
    }

    private func doseLine(_ item: ProtocolItem?, now: Date) -> String {
        guard let item else { return "" }
        return item.doseWithDrawText(on: now)
    }

    // MARK: Block pins (filtered to the selected block)

    @ViewBuilder
    private func blockPins(_ block: DayBlock, _ occ: [DoseOccurrence],
                           resting: [ProtocolItem], now: Date) -> some View {
        if occ.isEmpty && resting.isEmpty {
            calmLine(block.emptyLine, peek: peekNext(after: block, now: now))
        } else {
            VStack(spacing: VT.sCardGap) {
                ForEach(occ) { o in pin(o, now: now) }
                ForEach(resting) { item in restingRow(item, now: now) }
            }
        }
    }

    private func calmLine(_ text: String, peek: (DayBlock, Int)?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(text)
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
            if let (b, n) = peek {
                Text("Next: \(b.title.lowercased()), \(n) to pin")
                    .font(.system(size: 14)).foregroundStyle(VT.micro)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    @ViewBuilder
    private func pin(_ o: DoseOccurrence, now: Date) -> some View {
        if let item = items.first(where: { $0.id == o.itemID }) {
            let chip = item.schedule.flatMap {
                $0.hasCycle ? ScheduleService.cycleStatus(for: $0, on: now)?.chipText : nil
            }
            let state = ScheduleService.state(itemID: o.itemID, minutes: o.minutes, day: now,
                                              logs: logs, now: now)
            PinRow(name: item.displayName,
                   dose: item.doseWithDrawText(on: now),
                   time: o.timeText,
                   category: item.category,
                   state: state,
                   cycleChip: chip,
                   overdueText: state == .overdue
                       ? ScheduleService.overdueLabel(minutesLate: minutes(of: now) - o.minutes)
                       : nil,
                   onTake: { logAnimated(item, o, status: .taken) },
                   onSkip: { logAnimated(item, o, status: .skipped) },
                   onUndo: { withAnimation(reduceMotion ? VMotion.reduced : VMotion.cardEntrance) {
                       logger.undo(item: item, occurrence: o) } },
                   onOpenDetail: { openDetail(item) },
                   siteText: siteText(for: item, occurrence: o, state: state, now: now),
                   onTakeAtSite: item.isInjectable
                       ? { logAnimated(item, o, status: .taken, site: $0) } : nil,
                   onEdit: {
                       // Re-resolve at action time: a context menu can outlive
                       // its item (deleted from the Stack tab meanwhile).
                       let svc = StackService(context: context)
                       if let live = svc.items().first(where: { $0.id == item.id }) {
                           editDraft = svc.draft(for: live)
                       }
                   })
        }
    }

    // MARK: Resting rows (cycled-off items — quiet, never due/overdue)

    private func restingItemsByBlock(on date: Date) -> [DayBlock: [ProtocolItem]] {
        var out: [DayBlock: [ProtocolItem]] = [:]
        for item in items {
            guard let rule = item.schedule, rule.frequency != .prn,
                  ScheduleService.isResting(rule, on: date) else { continue }
            let block = DayBlock.from(minutes: rule.timeSlotsMinutes.min() ?? DayBlock.morning.defaultMinutes)
            out[block, default: []].append(item)
        }
        return out
    }

    private func restingRow(_ item: ProtocolItem, now: Date) -> some View {
        HStack(spacing: 12) {
            CompoundTile(category: item.category, size: 34).opacity(0.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName)
                    .font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.body)
                Text(ScheduleService.restingLine(for: item, on: now))
                    .font(.system(size: 13)).foregroundStyle(VT.micro)
            }
            Spacer()
            CycleChip(text: "Rest", resting: true)
        }
        .padding(.horizontal, 16).padding(.vertical, 14)
        .vtCard().opacity(0.7)
        .accessibilityElement(children: .combine)
    }

    // MARK: As needed (PRN)

    private func asNeededCard(now: Date) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AS NEEDED")
                .font(.system(size: 12, weight: .medium)).tracking(0.4)
                .textCase(.uppercase).foregroundStyle(VT.micro)
            ForEach(prnItems) { item in
                HStack(spacing: 12) {
                    CompoundTile(category: item.category, size: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.displayName)
                            .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.ink)
                        Text(prnSubtitle(item, now: now))
                            .font(.system(size: 12)).vtTabular().foregroundStyle(VT.micro)
                    }
                    Spacer()
                    Button {
                        logger.logPRN(item: item); Haptics.commit()
                    } label: {
                        Text("Log now")
                            .font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.dose)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .background(VT.dose.opacity(0.10), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    private func prnSubtitle(_ item: ProtocolItem, now: Date) -> String {
        if let last = logger.lastPRN(itemID: item.id, on: now) {
            return "logged \(relativeAgo(last.loggedAt, now: now))"
        }
        return item.doseText
    }

    private func relativeAgo(_ date: Date, now: Date) -> String {
        let mins = max(0, Int(now.timeIntervalSince(date) / 60))
        if mins < 1 { return "just now" }
        if mins < 60 { return "\(mins)m ago" }
        return "\(mins / 60)h ago"
    }

    private var emptyStack: some View {
        VStack(spacing: 12) {
            Text("Nothing scheduled yet.")
                .font(.vtHeadline).foregroundStyle(VT.ink).multilineTextAlignment(.center)
            Text("Add peptides to your stack and they'll show up here.")
                .font(.system(size: 15)).foregroundStyle(VT.body).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.top, 56)
    }

    // MARK: Derived state helpers

    private func isActed(_ o: DoseOccurrence, now: Date) -> Bool {
        switch ScheduleService.state(itemID: o.itemID, minutes: o.minutes, day: now, logs: logs, now: now) {
        case .taken, .skipped: return true
        case .due, .overdue: return false
        }
    }

    private func occurrencesByBlock(on date: Date) -> [DayBlock: [DoseOccurrence]] {
        var out: [DayBlock: [DoseOccurrence]] = [:]
        for item in items {
            for o in ScheduleService.occurrences(for: item, on: date) {
                out[o.block, default: []].append(o)
            }
        }
        for k in out.keys { out[k]?.sort { $0.minutes < $1.minutes } }
        return out
    }

    private func nextUnacted(in occ: [DoseOccurrence], now: Date) -> DoseOccurrence? {
        let m = minutes(of: now)
        let pending = occ.filter { !isActed($0, now: now) }
        return pending.filter { $0.minutes >= m }.min { $0.minutes < $1.minutes }
            ?? pending.min { $0.minutes < $1.minutes }
    }

    private func peekNext(after block: DayBlock, now: Date) -> (DayBlock, Int)? {
        let grouped = occurrencesByBlock(on: now)
        for b in DayBlock.allCases where b.rawValue > block.rawValue {
            let pending = (grouped[b] ?? []).filter { !isActed($0, now: now) }
            if !pending.isEmpty { return (b, pending.count) }
        }
        return nil
    }

    private func countLine(remaining: Int) -> String {
        if remaining == 0 { return "All done for today." }
        let words = ["zero", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine"]
        let n = remaining < words.count ? words[remaining] : "\(remaining)"
        return remaining == 1 ? "\(n) dose left." : "\(n) doses left."
    }

    private func blockBinding(default current: DayBlock) -> Binding<String> {
        Binding(get: { selectedBlock ?? blockID(current) }, set: { selectedBlock = $0 })
    }

    private func blockID(_ b: DayBlock) -> String {
        switch b { case .morning: "morning"; case .midday: "midday"; case .night: "night" }
    }
    private func blockIndex(_ id: String) -> Int? {
        switch id { case "morning": 0; case "midday": 1; case "night": 2; default: nil }
    }

    private func minutes(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
    private func dateFor(minutes m: Int) -> Date {
        Calendar.current.date(bySettingHour: m / 60, minute: m % 60, second: 0, of: Date()) ?? Date()
    }
}

// MARK: - Day-complete + rest-day cards

/// Shown when every scheduled dose is acted: warm cream wash + one brown bloom.
private struct DayCompleteCard: View {
    var body: some View {
        VStack(spacing: 6) {
            Text("All done for today.")
                .font(VFont.display(20, weight: .bold, relativeTo: .title3)).foregroundStyle(VT.ink)
            Text("Nicely done.")
                .font(.system(size: 14)).foregroundStyle(VT.micro)
        }
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .padding(VT.sCardPad)
        .background(VT.why.opacity(0.06), in: RoundedRectangle(cornerRadius: VT.rCard, style: .continuous))
    }
}

/// Shown on a rest day (nothing scheduled). Calm, distinct from the all-done card.
private struct RestDayCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Nothing scheduled today.")
                .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
            Text("A rest day.")
                .font(.system(size: 14)).foregroundStyle(VT.micro)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }
}
