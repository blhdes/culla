import SwiftUI
import SwiftData

struct InsightsView: View {
    @Query private var allSortedPhotos: [SortedPhoto]
    @Query private var dismissedPhotos: [DismissedPhoto]
    @Query(sort: \Gallery.displayOrder) private var galleries: [Gallery]

    @AppStorage("totalDeletedPhotos") private var totalDeletedPhotos = 0

    @State private var viewModel = InsightsViewModel()
    @Environment(\.dismiss) private var dismiss

    /// Only photos the user actually sorted in the app — excludes imports.
    private var sortedPhotos: [SortedPhoto] {
        allSortedPhotos.filter { !$0.isImported }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sortedPhotos.isEmpty && totalDeletedPhotos == 0 {
                    emptyState
                } else {
                    statsContent
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
            .task {
                viewModel.loadLibraryCount()
                viewModel.calculateStreaks(from: sortedPhotos.map(\.sortedAt))
            }
            .onChange(of: sortedPhotos.count) {
                viewModel.calculateStreaks(from: sortedPhotos.map(\.sortedAt))
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Start sorting to see\nyour progress here")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
    }

    // MARK: - Stats Content

    private var statsContent: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Hero stat
                VStack(spacing: 4) {
                    Text("\(sortedPhotos.count)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("photos sorted")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 24)
                .padding(.bottom, 8)

                // Streak row
                HStack(spacing: 24) {
                    streakBadge(
                        icon: "flame.fill",
                        value: viewModel.currentStreak,
                        label: "Current"
                    )
                    streakBadge(
                        icon: "trophy.fill",
                        value: viewModel.longestStreak,
                        label: "Best"
                    )
                }
                .padding(.horizontal)

                // Details card
                VStack(spacing: 0) {
                    detailRow("Deleted", value: "\(totalDeletedPhotos)")
                    detailRow("Remaining", value: "\(remainingCount)")
                    detailRow("Galleries", value: "\(galleries.count)")
                    detailRow("Top this week", value: mostActiveGalleryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Computed Stats

    private var remainingCount: Int {
        max(viewModel.totalLibraryCount - allSortedPhotos.count, 0)
    }

    private var mostActiveGalleryText: String {
        let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: .now)!
        let recentPhotos = sortedPhotos.filter { $0.sortedAt > cutoff }

        var counts: [UUID: (name: String, count: Int)] = [:]
        for photo in recentPhotos {
            guard let gallery = photo.gallery else { continue }
            let existing = counts[gallery.id]
            counts[gallery.id] = (gallery.name, (existing?.count ?? 0) + 1)
        }

        guard let top = counts.values.max(by: { $0.count < $1.count }) else {
            return "—"
        }
        return "\(top.name) (\(top.count))"
    }

    // MARK: - Components

    private func streakBadge(icon: String, value: Int, label: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(value > 0 ? .orange : .secondary)
                Text(value > 0 ? "\(value)" : "—")
                    .font(.title2)
                    .fontWeight(.bold)
                    .monospacedDigit()
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private func detailRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.body)
        .padding(.vertical, 8)
    }
}
