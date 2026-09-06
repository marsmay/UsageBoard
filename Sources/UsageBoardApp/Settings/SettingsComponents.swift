import SwiftUI
import UsageBoardCore

// MARK: - Shared Components

struct SettingsSection<Content: View>: View {
    var title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct SettingsRow<Content: View>: View {
    var label: String
    var hint: String? = nil
    var labelWidth: CGFloat? = nil
    var required: Bool = false
    @ViewBuilder var value: Content

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    Text(label)
                        .font(UB.Font.formLabel)
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    if required {
                        Text("*").foregroundStyle(.red)
                    }
                }
                if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(width: labelWidth, alignment: .leading)
            .frame(maxWidth: labelWidth == nil ? .infinity : nil, alignment: .leading)
            value
                .frame(maxWidth: labelWidth == nil ? nil : .infinity, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}
