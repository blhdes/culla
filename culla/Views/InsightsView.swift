import SwiftUI
import SwiftData
import Charts

struct InsightsView: View {
    @Query private var allSortedPhotos: [SortedPhoto]
    @Query private var dismissedPhotos: [DismissedPhoto]
    @Query(sort: \Gallery.displayOrder) private var galleries: [Gallery]

    @AppStorage("totalDeletedPhotos") private var totalDeletedPhotos = 0
    @AppStorage("totalSkippedPhotos") private var totalSkippedPhotos = 0
    @AppStorage("totalFavouritedPhotos") private var totalFavouritedPhotos = 0
    @AppStorage("statusBarVisible") private var statusBarVisible = false
    @AppStorage("totalReclaimedBytes") private var totalReclaimedBytes = 0.0

    @State private var viewModel = InsightsViewModel()
    @State private var allDailyStats: [DailyStats] = []
    @State private var isLoaded = false
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// Only photos the user actually sorted in the app — excludes imports.
    private var sortedPhotos: [SortedPhoto] {
        allSortedPhotos.filter { !$0.isImported }
    }

    var body: some View {
        NavigationStack {
            Group {
                if !isLoaded {
                    ProgressView()
                } else if sortedPhotos.isEmpty && totalDeletedPhotos == 0 {
                    emptyState
                } else {
                    statsContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(.systemBackground).ignoresSafeArea())
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
                fetchDailyStats()
                isLoaded = true
            }
            .onChange(of: sortedPhotos.count) {
                viewModel.calculateStreaks(from: sortedPhotos.map(\.sortedAt))
            }
        }
        .statusBarHidden(!statusBarVisible)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 24) {
            HeroIconTile(systemName: "chart.line.uptrend.xyaxis", pulse: true)
            Text("Start sorting to see\nyour progress here")
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Stats Content

    private var statsContent: some View {
        ScrollView {
            VStack(spacing: 22) {
                // Hero stat — the count ticks up via numericText when it changes.
                VStack(spacing: 4) {
                    Text("\(sortedPhotos.count)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy, value: sortedPhotos.count)
                    Text("photos sorted")
                        .font(.system(.subheadline, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 16)

                // Streak row
                HStack(spacing: 14) {
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

                // Details card
                GlassPanel(icon: "square.stack.3d.up.fill", title: "Details") {
                    VStack(spacing: 0) {
                        detailRow("Deleted", value: "\(totalDeletedPhotos)")
                        detailRow("Remaining", value: "\(remainingCount)")
                        detailRow("Galleries", value: "\(galleries.count)")
                        detailRow("Skipped", value: "\(totalSkippedPhotos)")
                        detailRow("Favourites", value: "\(totalFavouritedPhotos)")
                        detailRow("Top this week", value: mostActiveGalleryText)
                    }
                }

                // 7-day activity chart
                activityChart

                // Storage reclaimed — shown once any photos have been deleted.
                // The photo count mirrors the Deleted row; bytes may still be 0
                // for deletions made before byte-tracking existed.
                if totalDeletedPhotos > 0 {
                    storageHighlight
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 40)
        }
        .scrollContentBackground(.hidden)
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
        let startDay = calendar.date(byAdding: .day, value: -7, to: today)!
        let days = (0..<8).map { calendar.date(byAdding: .day, value: $0, to: startDay)! }

        // Group sorted photos by day
        let sortedByDay = Dictionary(
            grouping: sortedPhotos.filter { $0.sortedAt >= startDay },
            by: { calendar.startOfDay(for: $0.sortedAt) }
        ).mapValues { $0.count }

        // Match DailyStats to each day using calendar comparison —
        // avoids Date-equality precision issues with Dictionary keys.
        return days.flatMap { day in
            let stats = allDailyStats.filter { calendar.isDate($0.date, inSameDayAs: day) }
            let skipped    = stats.reduce(0) { $0 + $1.skipped }
            let deleted    = stats.reduce(0) { $0 + $1.deletedCount }
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
        GlassPanel(icon: "chart.xyaxis.line", title: "Last 7 days") {
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
    }

    /// Storage freed by deleting photos through Culla. Measured at delete time
    /// in `PhotoLibraryService` and accumulated into `totalReclaimedBytes`.
    private var storageHighlight: some View {
        GlassPanel(icon: "internaldrive.fill", title: "Storage") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(reclaimedText)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("reclaimed")
                        .font(.system(.headline, design: .rounded).weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text("Freed by deleting \(totalDeletedPhotos) photos")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Human-readable freed-space string, e.g. "2.3 GB".
    private var reclaimedText: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalReclaimedBytes), countStyle: .file)
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

    // MARK: - Data

    private func fetchDailyStats() {
        // Use a fresh context to read directly from the persistent store,
        // bypassing any stale state in the shared main context.
        let ctx = ModelContext(modelContext.container)
        allDailyStats = (try? ctx.fetch(FetchDescriptor<DailyStats>())) ?? []
    }

    // MARK: - Components

    private func streakBadge(icon: String, value: Int, label: String) -> some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .foregroundStyle(value > 0 ? .orange : .secondary)
                    .symbolEffect(.bounce, value: value)
                Text(value > 0 ? "\(value)" : "—")
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            Text(label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .glassSurface(in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.06), lineWidth: 1)
        )
        .animation(.snappy, value: value)
    }

    private func detailRow(_ label: LocalizedStringKey, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.system(.body, design: .rounded))
        .padding(.vertical, 8)
    }
}
