import SwiftUI

struct BadgeButtonLabel: View {
    let title: String
    let badgeCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .overlay(alignment: .topTrailing) {
            CountBadgeLabel(count: badgeCount)
                .offset(x: 8, y: -8)
                .accessibilityHidden(true)
        }
    }
}
