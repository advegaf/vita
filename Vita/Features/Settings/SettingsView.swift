import SwiftUI
import SwiftData
import UserNotifications

/// The Settings sheet (off the Today "…"). Custom grouped cards on the cream
/// canvas — profile, Apple Health, units, notifications, AI key, ℞ overrides,
/// privacy & consent, about, and a danger zone. Everything reuses the existing
/// data layer (AppSettings/UserProfile singletons, Keychain, HealthKitService).
struct SettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var settingsList: [AppSettings]
    @Query private var profileList: [UserProfile]

    // Profile mirrors (loaded from the profile on appear; persisted on blur/Done).
    @State private var nameText = ""
    @State private var ageText = ""
    @State private var sex = ""
    @State private var weightText = ""
    @State private var heightCmText = ""
    @State private var feetText = ""
    @State private var inchesText = ""
    @FocusState private var editing: Bool

    @AppStorage("vita.weightUnit") private var storedWeightUnit = WeightUnit.lb.rawValue
    @AppStorage("vita.measureUnit") private var storedMeasureUnit = MeasurementUnit.inch.rawValue
    @AppStorage("vita.heightUnit") private var heightUnitRaw = HeightUnit.ftIn.rawValue

    // Apple Health
    @State private var healthConnecting = false
    @State private var healthNote: String?
    // Notifications
    @State private var notifDenied = false
    // AI
    @State private var hasKey = false
    @State private var showKeyField = false
    @State private var keyDraft = ""
    @State private var testing = false
    @State private var testResult: String? = nil
    // Data export
    @State private var exportURLs: [URL] = []
    @State private var showExportShare = false
    // Physician report
    @State private var reportURL: URL?
    @State private var showReportShare = false
    // Danger
    @State private var pendingDanger: DangerKind?
    @State private var debugRx = false

    private let sexes = ["female", "male", "other"]
    private var settings: AppSettings? { settingsList.first }
    private var profile: UserProfile? { profileList.first }
    private var weightUnit: WeightUnit { WeightUnit(rawValue: storedWeightUnit) ?? .lb }
    private var measureUnit: MeasurementUnit { MeasurementUnit(rawValue: storedMeasureUnit) ?? .inch }
    private var heightUnit: HeightUnit { HeightUnit(rawValue: heightUnitRaw) ?? .ftIn }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: VT.sCardGap) {
                    ScreenHeader(eyebrow: "Settings", title: "Your setup.")
                        .padding(.bottom, 2)
                    profileCard
                    if HealthKitService.isAvailable { healthCard }
                    appearanceCard
                    unitsCard
                    notificationsCard
                    aiCard
                    rxCard
                    privacyCard
                    dataCard
                    aboutCard
                    dangerCard.id("bottom")
                }
                .padding(VT.sSection)
            }
            .onAppear {
                #if DEBUG
                if ProcessInfo.processInfo.environment["VITA_SETTINGS_SCROLL"] == "1" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }
                }
                if ProcessInfo.processInfo.environment["VITA_OPEN_RX"] == "1" {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { debugRx = true }
                }
                #endif
            }
            .navigationDestination(isPresented: $debugRx) { RxOverridesView() }
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .dismissesKeyboardOnTap()
            .background(VT.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { persistProfile(); dismiss() }.foregroundStyle(VT.ink)
                }
            }
        }
        .onAppear { loadProfile(); hasKey = Keychain.hasAPIKey() }
        .onChange(of: editing) { _, focused in if !focused { persistProfile() } }
        .task { await refreshNotifStatus() }
        .confirmationDialog(pendingDanger?.title ?? "",
                            isPresented: Binding(get: { pendingDanger != nil },
                                                 set: { if !$0 { pendingDanger = nil } }),
                            titleVisibility: .visible, presenting: pendingDanger) { kind in
            Button(kind.button, role: .destructive) { perform(kind) }
            Button("Cancel", role: .cancel) {}
        } message: { kind in Text(kind.message) }
    }

    // MARK: Profile

    private var profileCard: some View {
        card("Profile.", VT.dose) {
            vtFieldShell("Name") {
                TextField("What should vita call you?", text: $nameText).focused($editing)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
                    .textInputAutocapitalization(.words)
            }
            vtPlainField("Age", text: $ageText, suffix: "yrs", keyboard: .numberPad, focus: $editing)
            VStack(alignment: .leading, spacing: 6) {
                Text("Sex").font(.system(size: 13)).foregroundStyle(VT.micro)
                HStack(spacing: 8) {
                    ForEach(sexes, id: \.self) { s in
                        PillToggle(title: s.capitalized, isOn: sex == s) {
                            sex = (sex == s ? "" : s); persistProfile()
                        }
                    }
                }
            }
            vtFieldShell("Weight") {
                TextField("", text: $weightText).keyboardType(.decimalPad).focused($editing)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
                vtUnitTab(weightUnit.rawValue, action: toggleWeightUnit)
            }
            heightField
        }
    }

    @ViewBuilder
    private var heightField: some View {
        if heightUnit == .cm {
            vtFieldShell("Height") {
                TextField("", text: $heightCmText).keyboardType(.decimalPad).focused($editing)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
                vtUnitTab("cm", action: toggleHeightUnit)
            }
        } else {
            vtFieldShell("Height") {
                TextField("ft", text: $feetText).keyboardType(.numberPad).focused($editing)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
                Text("ft").font(.system(size: 14)).foregroundStyle(VT.micro)
                TextField("in", text: $inchesText).keyboardType(.numberPad).focused($editing)
                    .font(.system(size: 17, weight: .semibold)).foregroundStyle(VT.ink)
                vtUnitTab("ft·in", action: toggleHeightUnit)
            }
        }
    }

    // MARK: Apple Health

    private var healthCard: some View {
        card("Apple Health.", VT.why) {
            Text("Read-only. Pulls weight, sleep, and HRV to ground your plan.")
                .font(.system(size: 13)).foregroundStyle(VT.micro)
            Button(action: resync) {
                HStack(spacing: 8) {
                    if healthConnecting { ProgressView().tint(VT.dose) }
                    Text(healthConnecting ? "Syncing…" : "Re-sync now")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(VT.dose)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 12)
                .background(VT.dose.opacity(0.10), in: Capsule())
            }
            .buttonStyle(.plain).allowsHitTesting(!healthConnecting)
            if let healthNote {
                Text(healthNote).font(.system(size: 13)).foregroundStyle(VT.micro)
            }
        }
    }

    // MARK: Units

    private var appearanceCard: some View {
        card("Appearance.", VT.why) {
            HStack(spacing: 8) {
                ForEach(AppAppearance.allCases, id: \.self) { mode in
                    PillToggle(title: mode.label,
                               isOn: (settings?.appearance ?? .system) == mode) {
                        settings?.appearance = mode
                        context.saveLogged("SettingsView")
                    }
                }
            }
        }
    }

    private var unitsCard: some View {
        card("Units.", VT.timing) {
            labeledToggles("Weight", left: "kg", right: "lb",
                           isLeft: weightUnit == .kg) { toggleWeightUnit() }
            labeledToggles("Measurements", left: "cm", right: "in",
                           isLeft: measureUnit == .cm) {
                storedMeasureUnit = (measureUnit == .cm ? MeasurementUnit.inch : .cm).rawValue
            }
        }
    }

    private func labeledToggles(_ label: String, left: String, right: String,
                                isLeft: Bool, toggle: @escaping () -> Void) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(VT.body)
            Spacer()
            HStack(spacing: 8) {
                PillToggle(title: left, isOn: isLeft, fillsWidth: false) { if !isLeft { toggle() } }
                PillToggle(title: right, isOn: !isLeft, fillsWidth: false) { if isLeft { toggle() } }
            }
        }
    }

    // MARK: Notifications

    private var notificationsCard: some View {
        card("Notifications.", VT.dose) {
            HStack {
                Text("Dose reminders").font(.system(size: 15)).foregroundStyle(VT.body)
                Spacer()
                PillToggle(title: (settings?.notificationsEnabled ?? true) ? "On" : "Off",
                           isOn: settings?.notificationsEnabled ?? true, fillsWidth: false) {
                    setNotifications(!(settings?.notificationsEnabled ?? true))
                }
            }
            if notifDenied {
                Text("Notifications are off in iOS Settings.")
                    .font(.system(size: 13)).foregroundStyle(VT.micro)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.dose).buttonStyle(.plain)
            }
            if settings?.notificationsEnabled ?? true {
                Rectangle().fill(VT.hairline).frame(height: 1).padding(.vertical, 2)
                quietHoursRows
                remindBeforeRow
                latePingRow
            }
        }
    }

    // MARK: Notification depth (quiet hours, pre-dose lead, overdue re-ping)

    @ViewBuilder
    private var quietHoursRows: some View {
        HStack {
            Text("Quiet hours").font(.system(size: 15)).foregroundStyle(VT.body)
            Spacer()
            PillToggle(title: (settings?.quietHoursEnabled ?? false) ? "On" : "Off",
                       isOn: settings?.quietHoursEnabled ?? false, fillsWidth: false) {
                settings?.quietHoursEnabled.toggle()
                saveAndRebuild()
            }
        }
        if settings?.quietHoursEnabled == true {
            HStack {
                Text("From").font(.system(size: 15)).foregroundStyle(VT.body)
                Spacer()
                DatePicker("", selection: minutesBinding(\.quietStartMinutes),
                           displayedComponents: .hourAndMinute).labelsHidden()
            }
            HStack {
                Text("Until").font(.system(size: 15)).foregroundStyle(VT.body)
                Spacer()
                DatePicker("", selection: minutesBinding(\.quietEndMinutes),
                           displayedComponents: .hourAndMinute).labelsHidden()
            }
            Text("Advisory notices wait until quiet hours end. Dose reminders still fire at their scheduled time.")
                .font(.system(size: 12)).foregroundStyle(VT.micro)
        }
    }

    private var remindBeforeRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Remind before").font(.system(size: 15)).foregroundStyle(VT.body)
            HStack(spacing: 8) {
                ForEach([0, 10, 30, 60], id: \.self) { m in
                    PillToggle(title: m == 0 ? "Off" : "\(m)m",
                               isOn: (settings?.preDoseLeadMinutes ?? 0) == m, fillsWidth: false) {
                        settings?.preDoseLeadMinutes = m
                        saveAndRebuild()
                    }
                }
            }
        }
    }

    private var latePingRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Overdue follow-up").font(.system(size: 15)).foregroundStyle(VT.body)
                Spacer()
                PillToggle(title: (settings?.latePingEnabled ?? true) ? "On" : "Off",
                           isOn: settings?.latePingEnabled ?? true, fillsWidth: false) {
                    settings?.latePingEnabled.toggle()
                    saveAndRebuild()
                }
            }
            Text("One quiet follow-up about 45 minutes after a missed reminder.")
                .font(.system(size: 12)).foregroundStyle(VT.micro)
        }
    }

    private func saveAndRebuild() {
        context.saveLogged("SettingsView")
        NotificationManager.rebuild(context: context)
    }

    /// Binds a minutes-from-midnight Int on AppSettings to a DatePicker Date.
    private func minutesBinding(_ key: ReferenceWritableKeyPath<AppSettings, Int>) -> Binding<Date> {
        Binding<Date>(
            get: {
                let m = settings?[keyPath: key] ?? 0
                return Calendar.current.date(bySettingHour: m / 60, minute: m % 60,
                                             second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                settings?[keyPath: key] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                saveAndRebuild()
            }
        )
    }

    // MARK: AI / API key

    private var aiCard: some View {
        card("AI.", VT.dose) {
            Text("Powered by Claude Opus 4.8. Your key lives only in this device's Keychain.")
                .font(.system(size: 13)).foregroundStyle(VT.micro)
            HStack(spacing: 6) {
                Circle().fill(hasKey ? VT.why : VT.micro).frame(width: 7, height: 7)
                Text(hasKey ? "Connected" : "Not configured")
                    .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.ink)
                Spacer()
                Button(showKeyField ? "Cancel" : (hasKey ? "Replace key" : "Add key")) {
                    withAnimation(reduceMotion ? nil : VMotion.segmentExpand) {
                        showKeyField.toggle(); keyDraft = ""; testResult = nil
                    }
                }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(VT.dose).buttonStyle(.plain)
            }
            if showKeyField {
                vtFieldShell("Anthropic API key") {
                    SecureField("sk-ant-…", text: $keyDraft)
                        .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.ink)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                HStack(spacing: 10) {
                    Button(action: testConnection) {
                        HStack(spacing: 6) {
                            if testing { ProgressView().tint(VT.dose) }
                            Text("Test connection").font(.system(size: 14, weight: .semibold))
                        }.foregroundStyle(VT.dose)
                    }.buttonStyle(.plain).allowsHitTesting(!testing)
                    Spacer()
                    Button("Save") { saveKey() }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(keyDraft.isEmpty ? VT.micro : VT.dose)
                        .buttonStyle(.plain).allowsHitTesting(!keyDraft.isEmpty)
                }
                // Result on its OWN full-width line so long messages (e.g. "Out of
                // credits. Top up at console.anthropic.com.") never truncate.
                if let testResult {
                    Text(testResult)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(testResult == "Connected ✓" ? VT.why : VT.overdue)
                        .lineLimit(3).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if hasKey && !showKeyField {
                Button("Remove key", role: .destructive) {
                    Keychain.delete(Keychain.apiKeyAccount); hasKey = false
                }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(VT.overdue).buttonStyle(.plain)
            }
        }
    }

    // MARK: ℞ overrides

    private var rxCard: some View {
        NavigationLink {
            RxOverridesView()
        } label: {
            HStack {
                vtLead("Prescription flags.", color: VT.why)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(VT.micro)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(VT.sCardPad).vtCard()
        }
        .buttonStyle(.plain)
    }

    // MARK: Privacy & consent

    private var privacyCard: some View {
        card("Privacy.", VT.why) {
            consentRow("Educational consent", date: profile?.consentedAt)
            consentRow("Lab-scan consent", date: settings?.labConsentedAt)
            if settings?.labConsentedAt != nil {
                Button("Revoke lab-scan consent") {
                    settings?.labConsentedAt = nil; context.saveLogged("SettingsView")
                }
                .font(.system(size: 14, weight: .semibold)).foregroundStyle(VT.dose).buttonStyle(.plain)
            }
            Text("Educational, not medical advice.")
                .font(.system(size: 12)).foregroundStyle(VT.micro).padding(.top, 2)
        }
    }

    private func consentRow(_ label: String, date: Date?) -> some View {
        HStack {
            Text(label).font(.system(size: 15)).foregroundStyle(VT.body)
            Spacer()
            Text(date.map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "n/a")
                .font(.system(size: 14)).vtTabular().foregroundStyle(VT.micro)
        }
    }

    // MARK: Data export (M15 — losing the phone must not mean losing every log)

    private var dataCard: some View {
        card("Data.", VT.why) {
            Text("Your records live on this device. Export a backup anytime.")
                .font(.system(size: 13)).foregroundStyle(VT.micro)
            Button("Export my data") { exportData() }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.dose)
                .buttonStyle(.plain)
            Text("Doses, diary, and lab values as JSON and CSV. Lab scan images stay on your phone.")
                .font(.system(size: 12)).foregroundStyle(VT.micro)
            Rectangle().fill(VT.hairline).frame(height: 1).padding(.vertical, 2)
            Button("Share report") { shareReport() }
                .font(.system(size: 15, weight: .semibold)).foregroundStyle(VT.dose)
                .buttonStyle(.plain)
            Text("A short PDF for your physician or coach: stack, adherence, weight, latest labs.")
                .font(.system(size: 12)).foregroundStyle(VT.micro)
        }
        .sheet(isPresented: $showExportShare) {
            ActivityShareSheet(items: exportURLs)
        }
        .sheet(isPresented: $showReportShare) {
            if let reportURL { ActivityShareSheet(items: [reportURL]) }
        }
    }

    private func shareReport() {
        let items = (try? context.fetch(FetchDescriptor<ProtocolItem>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        let metrics = (try? context.fetch(FetchDescriptor<BodyMetric>())) ?? []
        let panels = (try? context.fetch(FetchDescriptor<LabPanel>())) ?? []
        let report = ReportBuilder.build(
            items: items, logs: logs, metrics: metrics, panels: panels,
            profile: profile, weightUnit: weightUnit)
        do {
            reportURL = try ReportPDF.write(report: report)
            showReportShare = true
            Haptics.press()
        } catch {
            NSLog("vita-report-FAILED: %@", String(describing: error))
        }
    }

    private func exportData() {
        let items = (try? context.fetch(FetchDescriptor<ProtocolItem>())) ?? []
        let logs = (try? context.fetch(FetchDescriptor<DoseLog>())) ?? []
        let entries = (try? context.fetch(FetchDescriptor<DiaryEntry>())) ?? []
        let metrics = (try? context.fetch(FetchDescriptor<BodyMetric>())) ?? []
        let panels = (try? context.fetch(FetchDescriptor<LabPanel>())) ?? []
        do {
            let json = try DataExport.json(items: items, logs: logs, entries: entries,
                                           metrics: metrics, panels: panels, appVersion: appVersion)
            let csv = DataExport.dosesCSV(logs: logs)
            exportURLs = try DataExport.writeFiles(json: json, csv: csv)
            showExportShare = true
            Haptics.press()
        } catch {
            NSLog("vita-export-FAILED: %@", String(describing: error))
        }
    }

    // MARK: About

    private var aboutCard: some View {
        card("About.", VT.why) {
            HStack {
                Text("Version").font(.system(size: 15)).foregroundStyle(VT.body)
                Spacer()
                Text(appVersion).font(.system(size: 14)).vtTabular().foregroundStyle(VT.micro)
            }
            Text("Your data stays on your device.")
                .font(.system(size: 13)).foregroundStyle(VT.micro)
            Text("Educational, not medical advice.")
                .font(.system(size: 12)).foregroundStyle(VT.micro)
        }
    }

    private var appVersion: String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let b = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(v) (\(b))"
    }

    // MARK: Danger zone

    private var dangerCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            vtLead("Danger zone.", color: VT.overdue)
            dangerRow("Clear chat history", .clearChat)
            dangerRow("Clear dose logs", .clearLogs)
            dangerRow("Reset onboarding", .resetOnboarding)
            dangerRow("Full reset (wipe everything)", .fullReset)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
        .padding(.top, 6)
    }

    private func dangerRow(_ label: String, _ kind: DangerKind) -> some View {
        Button { pendingDanger = kind } label: {
            HStack {
                Text(label).font(.system(size: 15, weight: .medium)).foregroundStyle(VT.overdue)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold)).foregroundStyle(VT.overdue.opacity(0.5))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Card shell

    private func card(_ lead: String, _ color: Color,
                      @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            vtLead(lead, color: color)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(VT.sCardPad).vtCard()
    }

    // MARK: Actions

    private func loadProfile() {
        guard let p = profile else { return }
        nameText = p.preferredName ?? ""
        if let b = p.birthDate {
            ageText = Calendar.current.dateComponents([.year], from: b, to: Date()).year.map(String.init) ?? ""
        }
        sex = p.biologicalSexRaw ?? ""
        if let kg = p.weightKg {
            weightText = weightUnit == .kg ? Units.trim(kg) : Units.trim(Units.kgToLb(kg))
        }
        if let cm = p.heightCm {
            if heightUnit == .cm { heightCmText = Units.trim(cm) }
            else { let fi = Units.cmToFeetInches(cm); feetText = String(fi.feet); inchesText = String(fi.inches) }
        }
    }

    private func persistProfile() {
        guard let p = profile else { return }
        p.preferredName = nameText.nilIfEmpty
        if let age = Int(ageText), age > 0, age < 130 {
            p.birthDate = Calendar.current.date(byAdding: .year, value: -age, to: Date())
        }
        p.biologicalSexRaw = sex.isEmpty ? nil : sex
        if let w = Units.parseDouble(weightText), w > 0 {
            p.weightKg = weightUnit == .kg ? w : Units.lbToKg(w)
        }
        if heightUnit == .cm {
            if let cm = Units.parseDouble(heightCmText), cm > 0 { p.heightCm = cm }
        } else {
            let f = Int(feetText) ?? 0, i = Int(inchesText) ?? 0
            if f + i > 0 { p.heightCm = Units.feetInchesToCm(feet: f, inches: i) }
        }
        context.saveLogged("SettingsView")
    }

    private func toggleWeightUnit() {
        if let v = Units.parseDouble(weightText) {
            weightText = weightUnit == .kg ? Units.trim(Units.kgToLb(v)) : Units.trim(Units.lbToKg(v))
        }
        storedWeightUnit = (weightUnit == .kg ? WeightUnit.lb : .kg).rawValue
    }

    private func toggleHeightUnit() {
        if heightUnit == .cm {
            if let cm = Units.parseDouble(heightCmText) {
                let fi = Units.cmToFeetInches(cm); feetText = String(fi.feet); inchesText = String(fi.inches)
            }
            heightUnitRaw = HeightUnit.ftIn.rawValue
        } else {
            let f = Int(feetText) ?? 0, i = Int(inchesText) ?? 0
            if f + i > 0 { heightCmText = Units.trim(Units.feetInchesToCm(feet: f, inches: i)) }
            heightUnitRaw = HeightUnit.cm.rawValue
        }
    }

    private func resync() {
        healthConnecting = true
        healthNote = nil
        Task {
            let granted = await HealthKitService.shared.requestAuthorization()
            if granted {
                // Quick reads (weight + height + age + sex) update the profile + finish fast…
                let v = await HealthKitService.shared.profileVitals()
                await MainActor.run {
                    if let p = profile {
                        if let w = v.weightKg, w > 0 { p.weightKg = w }
                        if let h = v.heightCm, h > 0 { p.heightCm = h }
                        if let a = v.ageYears {
                            p.birthDate = Calendar.current.date(byAdding: .year, value: -a, to: Date())
                        }
                        if let s = v.biologicalSex { p.biologicalSexRaw = s }
                        context.saveLogged("SettingsView")
                    }
                    loadProfile()
                    healthConnecting = false
                }
                // …the 90-day weight backfill merges in the background.
                let weights = await HealthKitService.shared.weightSamples(daysBack: 90)
                await MainActor.run { DiaryService(context: context).mergeHealthWeights(weights) }
            } else {
                await MainActor.run {
                    healthNote = HealthKitService.isAvailable
                        ? "Couldn't reach Apple Health. Check access in the Health app."
                        : "Apple Health isn't available on this device."
                    healthConnecting = false
                }
            }
        }
    }

    private func setNotifications(_ on: Bool) {
        settings?.notificationsEnabled = on
        context.saveLogged("SettingsView")
        if on {
            Task {
                _ = await NotificationService.requestPermission()
                await refreshNotifStatus()
                await MainActor.run { NotificationManager.rebuild(context: context) }
            }
        } else {
            NotificationManager.rebuild(context: context)
        }
    }

    private func refreshNotifStatus() async {
        let s = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run { notifDenied = s.authorizationStatus == .denied }
    }

    private func testConnection() {
        testing = true; testResult = nil
        let draft = keyDraft
        Task {
            let client = AnthropicClient(keyProvider: { draft.isEmpty ? Keychain.apiKey : draft })
            let problem = await client.pingProblem()
            await MainActor.run { testResult = problem ?? "Connected ✓"; testing = false }
        }
    }

    private func saveKey() {
        guard !keyDraft.isEmpty else { return }
        Keychain.setAPIKey(keyDraft)
        hasKey = Keychain.hasAPIKey()
        withAnimation(reduceMotion ? nil : VMotion.segmentExpand) { showKeyField = false; keyDraft = "" }
    }

    private func perform(_ kind: DangerKind) {
        let actions = SettingsActions(context: context)
        switch kind {
        case .clearChat: actions.clearChat()
        case .clearLogs: actions.clearDoseLogs()
        case .resetOnboarding: actions.resetOnboarding(); dismiss()
        case .fullReset: actions.fullReset(); dismiss()
        }
    }
}

enum DangerKind: Identifiable {
    case clearChat, clearLogs, resetOnboarding, fullReset
    var id: Int { hashValue }
    var title: String {
        switch self {
        case .clearChat: "Clear chat history?"
        case .clearLogs: "Clear dose logs?"
        case .resetOnboarding: "Reset onboarding?"
        case .fullReset: "Full reset?"
        }
    }
    var button: String {
        switch self {
        case .clearChat: "Clear chat"
        case .clearLogs: "Clear logs"
        case .resetOnboarding: "Reset"
        case .fullReset: "Wipe everything"
        }
    }
    var message: String {
        switch self {
        case .clearChat: "Deletes your entire chat history."
        case .clearLogs: "Deletes all dose history and resets your streak. Your stack stays."
        case .resetOnboarding: "Runs the welcome wizard again with a fresh plan. Your history, diary, and labs stay."
        case .fullReset: "Deletes your stack, logs, diary, labs, and chat. This can't be undone."
        }
    }
}
