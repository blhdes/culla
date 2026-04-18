import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @Query private var allSortedPhotos: [SortedPhoto]
    @Query private var dismissedPhotos: [DismissedPhoto]
    @Query(sort: \Gallery.displayOrder) private var galleries: [Gallery]
    @Query private var allDailyStats: [DailyStats]

    @AppStorage("totalDeletedPhotos") private var totalDeletedPhotos = 0
    @AppStorage("totalSkippedPhotos") private var totalSkippedPhotos = 0
    @AppStorage("totalFavouritedPhotos") private var totalFavouritedPhotos = 0

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
                    detailRow("Skipped", value: "\(totalSkippedPhotos)")
                    detailRow("Favourites", value: "\(totalFavouritedPhotos)")
                    detailRow("Top this week", value: mostActiveGalleryText)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                // 7-day activity chart
                activityChart
            }
            .padding(.bottom, 40)
        }
    }

    // MARK: - Chart

    private struct ChartPoint: Identifiable {
        let id = UUID()
        let date: Date
        let count: Int
        let series: String
    }

    private var chartData: [ChartPoint] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let sevenDaysAgo = calendar.date(byAdding: .day, value: -6, to: today)!
        let days = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: sevenDaysAgo)! }

        // Group sorted photos by day
        let sortedByDay = Dictionary(
            grouping: sortedPhotos.filter { $0.sortedAt >= sevenDaysAgo },
            by: { calendar.startOfDay(for: $0.sortedAt) }
        ).mapValues { $0.count }

        // Match DailyStats to each day using calendar comparison —
        // avoids Date-equality precision issues with Dictionary keys.
        return days.flatMap { day in
            let stats = allDailyStats.filter { calendar.isDate($0.date, inSameDayAs: day) }
            let skipped    = stats.reduce(0) { $0 + $1.skipped }
            let deleted    = stats.reduce(0) { $0 + $1.deleted }
            let favourited = stats.reduce(0) { $0 + $1.favourited }
            return [
                ChartPoint(date: day, count: sortedByDay[day] ?? 0, series: "Sorted"),
                ChartPoint(date: day, count: skipped,               series: "Skipped"),
                ChartPoint(date: day, count: deleted,               series: "Deleted"),
                ChartPoint(date: day, count: favourited,            series: "Favourited"),
            ]
        }
    }

    private var activityChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 days")
                .font(.subheadline)
                .fontWeight(.semibold)
                .padding(.horizontal, 4)

            Chart(chartData) { point in
                LineMark(
                    x: .value("Day", point.date, unit: .day),
                    y: .value("Count", point.count)
                )
                .foregroundStyle(by: .value("Series", point.series))
            }
            .chartForegroundStyleScale([
                "Sorted":     Color.blue,
                "Skipped":    Color.orange,
                "Deleted":    Color.red,
                "Favourited": Color.green,
            ])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { value in
                    if let date = value.as(Date.self) {
                        AxisValueLabel {
                            Text(date, format: .dateTime.weekday(.abbreviated))
                                .font(.caption2)
                        }
                    }
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel()
                }
            }
            .chartLegend(position: .bottom, alignment: .center, spacing: 12)
            .frame(height: 180)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal)
    }

    // MARK: - Computed Stats

    private var remainingCount: Int {
        max(viewModel.totalLibraryCount - sortedPhotos.count, 0)
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
