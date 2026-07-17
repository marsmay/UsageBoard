import SwiftUI

struct PlanTag: View {
    var text: String
    var colorName: String?

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .tracking(0.5)
            .foregroundStyle(foreground)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(background)
            )
    }

    private var palette: (bg: Color, fg: Color) {
        // 显式 colorName 优先（插件可指定任意支持的颜色）。
        if let tint = Self.color(for: colorName) {
            return (tint.opacity(0.18), tint)
        }
        switch text.uppercased() {
        case "PRO":
            return (Color.blue.opacity(0.16), Color.blue)
        case "PLUS":
            return (Color.teal.opacity(0.16), Color.teal)
        case "TEAM":
            return (Color.purple.opacity(0.18), Color.purple)
        case "FREE":
            return (Color.gray.opacity(0.18), Color.gray)
        case "MAX", "MAX 5X", "MAX 20X":
            return (Color.orange.opacity(0.18), Color.orange)
        default:
            return (Color.gray.opacity(0.16), Color.secondary)
        }
    }

    private static func color(for name: String?) -> Color? {
        switch name?.lowercased() {
        case "blue": return .blue
        case "orange": return .orange
        case "gray", "grey": return .gray
        case "indigo": return .indigo
        case "purple": return .purple
        case "teal": return .teal
        case "green": return .green
        case "red": return .red
        case "yellow": return .yellow
        default: return nil
        }
    }

    private var background: Color { palette.bg }
    private var foreground: Color { palette.fg }
}
