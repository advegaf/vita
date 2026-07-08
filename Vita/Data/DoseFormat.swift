import Foundation

/// Shared dose display formatting. Doses stay in the compound's AUTHORED unit
/// (semaglutide mg, BPC-157 mcg) — no mcg to mg conversion. The syringe draw is
/// joined to the dose by a spaced bullet.
enum DoseFormat {
    /// "250 mcg • 10u" — dose joined to the syringe draw by a spaced bullet (U+2022,
    /// which passes CopyGuard's no-middle-dot rule). Returns just the dose when there
    /// is no vial draw. Single source for every dose+draw render site.
    static func doseWithDraw(dose: String, drawUnits: Double?) -> String {
        guard let u = drawUnits, u > 0 else { return dose }
        return "\(dose) • \(vtFormatUnits(u))u"
    }
}
