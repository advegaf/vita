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

    private var logger: DoseLogger { DoseLogger(context: context) }
    private var prnItems: [ProtocolItem] { items.filter { ($0.schedule?.frequency ?? .daily) == .prn } }

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
                        if total > 0 { Text(countLine(remaining: remaining)) }
                        Text(currentBlock.greeting)
                    }
                    .vtHeadlineStyle()
                }
                .padding(.bottom, 2)

                if items.isEmpty {
                    emptyStack
                } else {
                    if total == 0 && !hasResting {
                        RestDayCard()
                    } else if total > 0 && remaining == 0 {
                        DayCompleteCard()
                    } else if let next {
                        focusCard(next, now: now)
                    }

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
            onLog: { if let item { logger.log(item: item, occurrence: o, status: .taken) } }
        )
    }

    private func doseLine(_ item: ProtocolItem?, now: Date) -> String {
        guard let item else { return "" }
        let dose = item.effectiveDoseText(on: now)
        return item.effectiveDrawUnitsText(on: now).map { "\(dose) · \($0)" } ?? dose
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
                Text("Next: \(b.title.lowercased()) · \(n) to pin")
                    .font(.system(size: 14)).foregroundStyle(VT.micro)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    @ViewBuilder
    private func pin(_ o: DoseOccurrence, now: Date) -> some View {
        if let item = items.first(where: { $0.id == o.itemID }) {
            let dose = item.effectiveDoseText(on: now)
            let chip = item.schedule.flatMap {
                $0.hasCycle ? ScheduleService.cycleStatus(for: $0, on: now)?.chipText : nil
            }
            let state = ScheduleService.state(itemID: o.itemID, minutes: o.minutes, day: now,
                                              logs: logs, now: now)
            PinRow(name: item.displayName,
                   dose: item.effectiveDrawUnitsText(on: now).map { "\(dose) · \($0)" } ?? dose,
                   time: o.timeText,
                   category: item.category,
                   state: state,
                   cycleChip: chip,
                   overdueText: state == .overdue
                       ? ScheduleService.overdueLabel(minutesLate: minutes(of: now) - o.minutes)
                       : nil,
                   onTake: { logger.log(item: item, occurrence: o, status: .taken) },
                   onSkip: { logger.log(item: item, occurrence: o, status: .skipped) },
                   onUndo: { logger.undo(item: item, occurrence: o) },
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
            CycleChip(text: "rest", resting: true)
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
