import SwiftUI

enum NotedSpacing {
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}
enum NotedRadius {
    static let control: CGFloat = 10
    static let surface: CGFloat = 16
}

extension Color {
    static let notedPrimary = Color(red: 0.16, green: 0.30, blue: 0.22)
    static let notedPrimaryStrong = Color(red: 0.11, green: 0.23, blue: 0.16)
    static let notedRecording = Color(red: 0.72, green: 0.32, blue: 0.25)
    static let notedSuccess = Color(red: 0.29, green: 0.49, blue: 0.34)
    static let notedAttention = Color(red: 0.76, green: 0.48, blue: 0.14)
    static let notedMemory = Color(red: 0.43, green: 0.34, blue: 0.63)
}

struct StatusBadge: View {
    let title: String
    let color: Color
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, NotedSpacing.sm)
            .padding(.vertical, NotedSpacing.xs)
            .background(color.opacity(0.12), in: Capsule())
    }
}

struct NotedSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(NotedSpacing.lg)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: NotedRadius.surface))
    }
}
