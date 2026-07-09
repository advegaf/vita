import SwiftUI

/// One US-Letter page of the physician/coach report. Fixed 612x792pt frame, fixed
/// point-size fonts (print, not Dynamic Type), and a forced LIGHT palette so a
/// dark-mode phone never prints a dark report (colors are hardcoded light values,
/// not VT tokens, which are trait-adaptive).
struct ReportPageView: View {
    let page: ReportBuilder.ReportPage
    let generatedText: String
    let profileLine: String?
    let disclaimer: String

    private let ink = Color(hex: "1A1A1A")
    private let body_ = Color(hex: "6E6E6E")
    private let micro = Color(hex: "9A958C")
    private let hairline = Color(hex: "EAE6DF")

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if page.isFirst { header }
            if !page.stack.isEmpty { stackSection }
            if !page.adherence.isEmpty { adherenceSection }
            if let w = page.weight { weightSection(w) }
            if let l = page.labs { labsSection(l) }
            Spacer(minLength: 0)
            Text(disclaimer)
                .font(.system(size: 9)).foregroundStyle(micro)
        }
        .padding(48)
        .frame(width: 612, height: 792, alignment: .top)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Vita report")
                .font(.system(size: 24, weight: .bold)).foregroundStyle(ink)
            Text(generatedText).font(.system(size: 11)).foregroundStyle(micro)
            if let profileLine {
                Text(profileLine).font(.system(size: 11)).foregroundStyle(body_)
            }
        }
    }

    private func sectionTitle(_ t: String) -> some View {
        Text(t.uppercased())
            .font(.system(size: 10, weight: .semibold)).tracking(0.8)
            .foregroundStyle(micro)
    }

    private var stackSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Current protocol")
            ForEach(Array(page.stack.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline) {
                    Text(line.name).font(.system(size: 12, weight: .semibold)).foregroundStyle(ink)
                        .frame(width: 150, alignment: .leading)
                    Text(line.doseText).font(.system(size: 12)).monospacedDigit().foregroundStyle(body_)
                        .frame(width: 90, alignment: .leading)
                    Text(line.cadence).font(.system(size: 11)).foregroundStyle(body_)
                    Spacer()
                    Text(line.sinceText).font(.system(size: 10)).foregroundStyle(micro)
                }
                Rectangle().fill(hairline).frame(height: 0.5)
            }
        }
    }

    private var adherenceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Adherence")
            ForEach(Array(page.adherence.enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline) {
                    Text(line.name).font(.system(size: 12)).foregroundStyle(ink)
                        .frame(width: 150, alignment: .leading)
                    if line.isPRN {
                        Text("as needed, \(line.prn30) uses in 30 days")
                            .font(.system(size: 11)).monospacedDigit().foregroundStyle(body_)
                    } else {
                        Text("30 days: \(line.d30.logged) of \(line.d30.scheduled)")
                            .font(.system(size: 11)).monospacedDigit().foregroundStyle(body_)
                            .frame(width: 120, alignment: .leading)
                        Text("90 days: \(line.d90.logged) of \(line.d90.scheduled)")
                            .font(.system(size: 11)).monospacedDigit().foregroundStyle(body_)
                    }
                    Spacer()
                }
            }
        }
    }

    private func weightSection(_ w: ReportBuilder.WeightSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Weight")
            HStack(spacing: 16) {
                Text(w.currentText).font(.system(size: 13, weight: .semibold))
                    .monospacedDigit().foregroundStyle(ink)
                if let d = w.delta30Text {
                    Text(d).font(.system(size: 11)).monospacedDigit().foregroundStyle(body_)
                }
                if let d = w.delta90Text {
                    Text(d).font(.system(size: 11)).monospacedDigit().foregroundStyle(body_)
                }
            }
        }
    }

    private func labsSection(_ l: ReportBuilder.LabsSection) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Latest labs, \(l.dateText)" + (l.labName.map { ", \($0)" } ?? ""))
            ForEach(Array(l.rows.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .firstTextBaseline) {
                    Text(row.name).font(.system(size: 11)).foregroundStyle(ink)
                        .frame(width: 180, alignment: .leading)
                    Text(row.valueText).font(.system(size: 11)).monospacedDigit()
                        .foregroundStyle(row.isOutOfRange ? Color(hex: "C0593F") : body_)
                        .frame(width: 80, alignment: .leading)
                    Text(row.refText).font(.system(size: 10)).monospacedDigit().foregroundStyle(micro)
                    Spacer()
                    if !row.flagText.isEmpty {
                        Text(row.flagText).font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color(hex: "C0593F"))
                    }
                }
            }
        }
    }
}

#Preview {
    ReportPageView(
        page: .init(
            stack: [.init(name: "Semaglutide", doseText: "0.5 mg", cadence: "Weekly on Sun",
                          sinceText: "since Jun 1", isPRN: false)],
            adherence: [.init(name: "Semaglutide", d30: .init(logged: 4, scheduled: 4),
                              d90: .init(logged: 12, scheduled: 13), isPRN: false, prn30: 0)],
            weight: .init(currentText: "82.4 kg", delta30Text: "-1.2 kg over 30 days",
                          delta90Text: "-3.4 kg over 90 days"),
            labs: nil, isFirst: true),
        generatedText: "Generated July 8, 2026",
        profileLine: "34 yr, male, 82 kg",
        disclaimer: ReportBuilder.disclaimerText)
}
