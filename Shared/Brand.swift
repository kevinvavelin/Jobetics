import SwiftUI

/// Jobetics brand palette, sampled from the app icon (cyan → electric blue → violet).
nonisolated enum Brand {
    static let cyan = Color(red: 0.24, green: 0.94, blue: 1.0)
    static let blue = Color(red: 0.12, green: 0.36, blue: 1.0)
    static let indigo = Color(red: 0.35, green: 0.40, blue: 0.96)
    static let violet = Color(red: 0.54, green: 0.24, blue: 0.96)

    static let gradient = LinearGradient(
        colors: [cyan, blue, violet],
        startPoint: .topTrailing,
        endPoint: .bottomLeading
    )

    static let angular = AngularGradient(
        colors: [violet, blue, cyan, blue, violet],
        center: .center
    )

    static let positive = Color(red: 0.20, green: 0.78, blue: 0.55)
    static let warning = Color(red: 1.0, green: 0.62, blue: 0.20)
    static let danger = Color(red: 1.0, green: 0.30, blue: 0.36)
}
