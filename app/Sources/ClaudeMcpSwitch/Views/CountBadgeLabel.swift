import SwiftUI

struct CountBadgeLabel: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Text(badgeText)
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.red))
                .accessibilityLabel(accessibilityText)
        }
    }

    private var badgeText: String {
        count > 99 ? "99+" : String(count)
    }

    private var accessibilityText: String {
        count == 1 ? "1 change" : "\(count) changes"
    }
}
