import SwiftUI

/// Body copy in `body` gray with **ink-bold** emphasis on key terms.
/// Use `**term**` to mark a load-bearing term (renders bold + ink, like "2cm").
func vtBody(_ s: String, size: CGFloat = 16) -> Text {
    let parts = s.components(separatedBy: "**")
    var attr = AttributedString()
    for (i, part) in parts.enumerated() {
        var run = AttributedString(part)
        if i % 2 == 1 {
            run.font = .system(size: size, weight: .semibold)
            run.foregroundColor = VT.ink
        } else {
            run.font = .system(size: size, weight: .regular)
            run.foregroundColor = VT.body
        }
        attr += run
    }
    return Text(attr)
}

/// The period-punctuated colored lead word, inline at body size.
func vtLead(_ word: String, color: Color, size: CGFloat = 16) -> Text {
    Text(word).font(.system(size: size, weight: .semibold)).foregroundColor(color)
}
