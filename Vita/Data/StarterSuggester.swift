import Foundation

/// Maps chosen goals to a small starter set of catalog slugs (used when the user
/// picks goals but no peptides). Pure + unit-tested. The real AI replaces this in M3.
enum StarterSuggester {

    /// 1-2 representative compounds per goal.
    static func slugs(for goals: [GoalKind]) -> [String] {
        var out: [String] = []
        for g in goals {
            for s in map[g] ?? [] where !out.contains(s) { out.append(s) }
        }
        return out
    }

    static let map: [GoalKind: [String]] = [
        .fatLoss:         ["semaglutide"],
        .muscleStrength:  ["cjc-1295-ipamorelin"],
        .recoveryHealing: ["bpc-157", "tb-500"],
        .cognitionMood:   ["semax"],
        .sexualHealth:    ["pt-141"],
        .longevity:       ["nad"],
    ]
}
