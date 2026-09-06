import SwiftUI

private nonisolated(unsafe) let sharedTick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

struct CountdownLabel: View {
    var target: Date?
    @State private var now = Date()

    var body: some View {
        Text(formatted)
            .font(UB.Font.countdown)
            .foregroundStyle(.tertiary)
            .onReceive(sharedTick) { now = $0 }
    }

    private var formatted: String {
        guard let target else { return "-" }
        let seconds = target.timeIntervalSince(now)
        guard seconds.isFinite, seconds < Double(Int.max) else { return "-" }
        let remaining = Int(max(0, seconds))
        return String(format: "%02d:%02d", remaining / 60, remaining % 60)
    }
}
