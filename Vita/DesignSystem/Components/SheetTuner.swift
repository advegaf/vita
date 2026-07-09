import SwiftUI
import UIKit

/// Reaches the hosting `UISheetPresentationController` and force-enables
/// `prefersScrollingExpandsWhenScrolledToEdge`, re-asserting around SwiftUI's
/// own configuration passes.
///
/// Why (M38 spike finding): the card is a permanently-presented two-detent
/// sheet with `.presentationBackgroundInteraction(.enabled)` — non-modal so the
/// photo-layer header stays tappable. In that mode the Maps-style handoff
/// (upward pan on inner scroll content expands the sheet before content
/// scrolls) depends on this UIKit flag, which SwiftUI does not guarantee.
/// Verified by CardSpikeUITests.
struct SheetTuner: UIViewControllerRepresentable {
    /// Optional probe for tests/spikes: reports what was found and set.
    var report: (@MainActor (String) -> Void)? = nil

    func makeUIViewController(context: Context) -> TunerVC {
        let vc = TunerVC()
        vc.report = report
        return vc
    }
    func updateUIViewController(_ vc: TunerVC, context: Context) { vc.apply() }

    final class TunerVC: UIViewController {
        var report: (@MainActor (String) -> Void)?

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            apply()
        }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
            // SwiftUI applies its own sheet configuration after appearance;
            // re-assert once the current runloop turn settles.
            DispatchQueue.main.async { [weak self] in self?.apply() }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in self?.apply() }
        }
        func apply() {
            var vc: UIViewController? = self
            while let v = vc {
                if let sheet = v.sheetPresentationController {
                    if !sheet.prefersScrollingExpandsWhenScrolledToEdge {
                        sheet.prefersScrollingExpandsWhenScrolledToEdge = true
                    }
                    let undim = sheet.largestUndimmedDetentIdentifier?.rawValue ?? "nil"
                    report?("s=1 e=\(sheet.prefersScrollingExpandsWhenScrolledToEdge ? 1 : 0) u=\(undim.prefix(9))")
                    return
                }
                vc = v.parent
            }
            report?("s=0")
        }
    }
}
