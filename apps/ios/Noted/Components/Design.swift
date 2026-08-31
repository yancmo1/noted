import SwiftUI

enum AppSpacing {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let section: CGFloat = 24
    static let screen: CGFloat = 16
    static let card: CGFloat = 16
}

enum AppRadius {
    static let card: CGFloat = 16
}

extension Color {
    static let gardenInk = Color(red: 0.10, green: 0.12, blue: 0.18)
    static let gardenCream = Color(red: 0.97, green: 0.96, blue: 0.93)
    static let notedPrimary = Color(red: 0.16, green: 0.30, blue: 0.22)
    static let notedPrimaryStrong = Color(red: 0.11, green: 0.23, blue: 0.16)
    static let notedRecording = Color(red: 0.72, green: 0.32, blue: 0.25)
    static let notedSuccess = Color(red: 0.29, green: 0.49, blue: 0.34)
    static let notedAttention = Color(red: 0.76, green: 0.48, blue: 0.14)
    static let notedMemory = Color(red: 0.43, green: 0.34, blue: 0.63)
}

struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View { Text(text).font(.caption.bold()).padding(.horizontal, 9).padding(.vertical, 5).background(color.opacity(0.14), in: Capsule()).foregroundStyle(color).accessibilityLabel(text) }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let message: String
    var body: some View { ContentUnavailableView(title, systemImage: icon, description: Text(message)) }
}

func timeLabel(_ interval: TimeInterval) -> String { let total = Int(interval.rounded()); return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60) }
