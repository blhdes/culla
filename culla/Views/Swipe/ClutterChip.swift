import SwiftUI

/// The small glass label in the swipe screen's top-right corner when the
/// top card looks like clutter. Styled like the "12 / 340" counter.
///
/// Workshop line (2026-11-27): `place=corner look=glass content=icon+word
/// words=specific size=12 multi=strongest appear=fade`.
struct ClutterChip: View {
    let flag: ClutterFlag

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: flag.systemImage)
            Text(flag.title)
        }
        .font(.caption)
        .fontWeight(.medium)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .accessibilityElement(children: .combine)
    }
}
