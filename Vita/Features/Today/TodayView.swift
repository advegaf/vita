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

    @State private var editDraft: DoseDraft?
    @State private var showSettings = false
    @Query private var profiles: [UserProfile]
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
        .sheet(item: $editDraft) { d in DoseSetupSheet(draft: d) }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.environment["VITA_OPEN_SETTINGS"] == "1" {
                try? await Task.sleep(nanoseconds: 400_000_000)
                showSettings = true
            }
            #endif
        }
    }

    /// M40 mini-header (Lumina-style): avatar circle, gray greeting over the
    /// user's name, and the settings control in a white circle.
    private func greetingHeader(block: DayBlock) -> some View {
        HStack(spacing: 12) {
            avatarCircle
            VStack(alignment: .leading, spacing: 0) {
                Text("\(block.greeting.trimmingCharacters(in: CharacterSet(charactersIn: "."))) \(block.emoji)")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(VT.body)
                Text(profiles.first?.preferredName?.nilIfEmpty ?? "Your plan today")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(VT.ink)
            }
            Spacer()
            Button { showSettings = true } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(VT.ink)
                    .frame(width: 40, height: 40)
                    .background(VT.card, in: Circle())
                    .shadow(color: VT.shadowColor, radius: 6, y: 3)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
        }
        .accessibilityElement(children: .contain)
    }

    private var avatarCircle: some View {
        let initial = profiles.first?.preferredName?.nilIfEmpty.map { String($0.prefix(1)).uppercased() }
        return Circle()
            .fill(VT.card)
            .frame(width: 42, height: 42)
            .shadow(color: VT.shadowColor, radius: 6, y: 3)
            .overlay {
                if let initial {
                    Text(initial).font(.system(size: 17, weight: .bold)).foregroundStyle(VT.ink)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: 16)).foregroundStyle(VT.micro)
                }
            }
            .accessibilityHidden(true)
    }

    private func content(now: Date) -> some View {
        let currentBlock = DayBlock.from(minutes: minutes(of: now))
        let grouped = occurrencesByBlock(on: now)
        let allOcc = grouped.values.flatMap { $0 }
        let total = allOcc.count
        let acted = allOcc.filter { isActed($0, now: now) }.count
        let remaining = total - acted
        let next = nextUnacted(in: allOcc, now: now)
        let restingByBlock = restingItemsByBlock(on: now)

        return ScrollView {
            VStack(alignment: .leading, spacing: VT.sCardGap) {
                greetingHeader(block: currentBlock)
                    .padding(.bottom, 6)
                if items.isEmpty {
                    emptyStack
                } else {
                    // Editorial hero: one display headline carrying the day's state.
                    TodayHero(state: heroState(next: next, total: total, remaining: remaining,
                                               grouped: grouped, now: now))
                        .id(remaining == 0 ? "done" : (next?.id ?? "rest"))
                        .transition(reduceMotion ? .opacity
                            : .asymmetric(insertion: .opacity.combined(with: .offset(y: 8)),
                                          removal: .opacity))
                        .padding(.bottom, 4)

                    DateStrip(days: DateStrip.week(asOf: now, isDayDone: { isDayComplete($0) }))
                        .padding(.bottom, 6)

                    if let insight = insightLine(now: now) {
                        InsightCard(text: insight, style: .dashed) {
                            if lowVialLine != nil { NotificationRouter.shared.pendingTab = .stack }
                        }
                    }

                    // Journey timeline: every block stacked, gray group labels,
                    // the NEXT pending dose as the black card.
                    ForEach(DayBlock.allCases, id: \.self) { block in
                        let occ = grouped[block] ?? []
                        let resting = restingByBlock[block] ?? []
                        if !occ.isEmpty || !resting.isEmpty {
                            Text(block.title)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(VT.micro)
                                .padding(.top, 8).padding(.leading, 4)
                            ForEach(occ) { o in
                                if o.id == next?.id {
                                    nextDoseCard(o, now: now)
                                } else {
                                    pin(o, now: now)
                                }
                            }
                            ForEach(resting) { item in restingRow(item, now: now) }
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

    // MARK: Hero state + insight

    private func heroState(next: DoseOccurrence?, total: Int, remaining: Int,
                           grouped: [DayBlock: [DoseOccurrence]], now: Date) -> TodayHero.State {
        guard total > 0 else { return .restDay }
        guard remaining > 0, let next else { return .allDone }
        let item = items.first { $0.id == next.itemID }
        let compound = item?.displayName ?? "dose"
        let state = ScheduleService.state(itemID: next.itemID, minutes: next.minutes,
                                          day: now, logs: logs, now: now)
        if state == .overdue {
            return .overdue(compound: compound, time: next.timeText)
        }
        let pendingInBlock = (grouped[next.block] ?? []).filter { !isActed($0, now: now) }.count
        return .upNext(block: next.block.title, compound: compound,
                       count: pendingInBlock, time: next.timeText)
    }

    /// Rule-based lavender insight: streak + supply, quiet and optional.
    private func insightLine(now: Date) -> String? {
        let streak = StreakService.currentStreak(items: items, logs: logs, asOf: now)
        switch (streak >= 3, lowVialLine) {
        case (true, let vial?):  return "You're \(streak) days consistent. \(vial)."
        case (true, nil):        return "You're \(streak) days consistent. Keep it up."
        case (false, let vial?): return "\(vial). Plan the refill ahead."
        case (false, nil):       return nil
        }
    }

    /// A past day is "complete" when every scheduled occurrence has a log.
    private func isDayComplete(_ date: Date) -> Bool {
        let start = Calendar.current.startOfDay(for: date)
        var anyScheduled = false
        for item in items {
            for o in ScheduleService.occurrences(for: item, on: date) {
                anyScheduled = true
                if !logs.contains(where: {
                    DoseLogger.matches($0, itemID: o.itemID, dayStart: start, minutes: o.minutes)
                }) { return false }
            }
        }
        return anyScheduled
    }

    // MARK: Next dose (the black card)

    private func nextDoseCard(_ o: DoseOccurrence, now: Date) -> some View {
        let item = items.first { $0.id == o.itemID }
        let state = ScheduleService.state(itemID: o.itemID, minutes: o.minutes, day: now,
                                          logs: logs, now: now)
        return NextDoseCard(
            name: item?.displayName ?? "",
            doseLine: item?.doseWithDrawText(on: now) ?? "",
            timeText: o.timeText,
            siteLine: item.flatMap { i in
                i.isInjectable ? SiteRotation.next(for: i, logs: logs).map { "→ \($0.label)" } : nil
            },
            category: item?.category ?? .other,
            overdueText: state == .overdue
                ? ScheduleService.overdueLabel(minutesLate: minutes(of: now) - o.minutes) : nil,
            onLog: { if let item { logAnimated(item, o, status: .taken) } },
            onOpenDetail: { if let item { openDetail(item) } }
        )
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


    private func minutes(of date: Date) -> Int {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }
}

