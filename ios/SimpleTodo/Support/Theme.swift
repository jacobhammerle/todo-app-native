import SwiftUI
import UIKit

/// Colors from the Expo design-system tokens the original app uses
/// (brand-blue, status-success, status-danger), light and dark.
enum Brand {
    static let tint = dynamic(light: 0x0072DE, dark: 0x4AA8FF)
    static let success = dynamic(light: 0x098D48, dark: 0x4ADE80)
    static let danger = dynamic(light: 0xCF222E, dark: 0xFF7A7A)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
