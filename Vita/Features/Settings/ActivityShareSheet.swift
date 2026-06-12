import SwiftUI
import UIKit

/// Thin wrapper for the system share sheet (used by the data export — ShareLink
/// wants its payload eagerly, but export files are built on tap).
struct ActivityShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}
