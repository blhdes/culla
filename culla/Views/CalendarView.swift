import SwiftUI
import UIKit

// MARK: - Pre-computed Data Models

/// One calendar day's static info — computed once, never recalculated during render.
struct DayInfo: Identifiable, Equatable {
    let id: Date          // startOfDay — used as dictionary key into photo data
    let dayNumber: Int    // 1–31
    let isToday: Bool
    let isEnabled: Bool
}

/// Wraps an optional DayInfo with a stable grid-position ID for ForEach.
struct DaySlot: Identifiable, Equatable {
    let id: Int        // grid position within month (0–41)
    let info: DayInfo?
}

/// One row of 7 day slots with a stable identity.
struct WeekRow: Identifiable, Equatable {
    let id: Int        // week index within month (0–5)
    let slots: [DaySlot]
}

/// One month's worth of pre-computed grid data.
struct CalendarMonth: Identifiable {
    let id: Date          // first-of-month — used as scroll anchor
    let title: String     // "April 2024"
    let weeks: [WeekRow]  // pre-computed, stored — not re-sliced on each render
}

/// Everything the calendar needs to render — assigned in a single @State mutation.
private struct CalendarViewData {
    let months: [CalendarMonth]
    let photoCounts: [Date: Int]
    let thumbnailIDs: [Date: [String]]
}

// MARK: - CalendarView

struct CalendarView: View {
    @Binding var selectedDate: Date
    var earliest: Date = .distantPast
    var latest: Date = .distantFuture
    var albumIdentifier: String? = nil

    @State private var viewData: CalendarViewData?

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        Group {
            if let viewData {
                let selectedDay = calendar.startOfDay(for: selectedDate)

                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 4) {
                            weekdayHeader
                                .padding(.horizontal)
                                .padding(.bottom, 4)

                            ForEach(viewData.months) { month in
                                Text(month.title)
                                    .font(.body)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal)
                                    .padding(.top, 16)
                                    .padding(.bottom, 4)
                                    .id("title_\(month.id)")

                                ForEach(month.weeks) { week in
                                    LazyVGrid(columns: columns, spacing: 4) {
                                        ForEach(week.slots) { slot in
                                            DayCellView(
                                                slot: slot,
                                                isSelected: slot.info?.id == selectedDay,
                                                photoCount: slot.info.flatMap { viewData.photoCounts[$0.id] } ?? 0,
                                                thumbnailIDs: slot.info.flatMap { viewData.thumbnailIDs[$0.id] } ?? [],
                                                selectedDate: $selectedDate
                                            )
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        }
                        .padding(.vertical)
                    }
                    .onAppear {
                        proxy.scrollTo("title_\(calendar.startOfMonth(for: selectedDate))", anchor: .top)
                    }
                }
            } else {
                ProgressView()
            }
        }
        .task {
            let albumID = albumIdentifier
            let service = PhotoLibraryService.shared
            let e = earliest
            let l = latest
            let cal = calendar

            let (months, data) = await Task.detached(priority: .userInitiated) {
                let data = service.calendarData(from: e, to: l, inAlbum: albumID)
                let months = CalendarView.buildMonths(calendar: cal, earliest: e, latest: l)
                return (months, data)
            }.value

            // startCachingCalendarThumbnails is @MainActor — call it here after await.
            // PHCachingImageManager dispatches caching work to its own internal thread.
            let allIDs = data.thumbnailIDs.values.flatMap { $0 }
            service.startCachingCalendarThumbnails(allIDs)

            viewData = CalendarViewData(
                months: months,
                photoCounts: data.counts,
                thumbnailIDs: data.thumbnailIDs
            )
        }
        .onDisappear {
            PhotoLibraryService.shared.stopCachingAll()
        }
    }

    // MARK: - Weekday Header

    private var weekdayHeader: some View {
        LazyVGrid(columns: columns, spacing: 0) {
            ForEach(orderedWeekdaySymbols, id: \.self) { symbol in
                Text(symbol.uppercased())
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Pre-computation

    /// Builds all month/day data once on a background thread. Pure function — no instance state.
    private nonisolated static func buildMonths(calendar cal: Calendar, earliest: Date, latest: Date) -> [CalendarMonth] {
        let today = cal.startOfDay(for: .now)
        let enabledStart = cal.startOfDay(for: earliest)
        let enabledEnd = cal.startOfDay(for: latest)

        var result: [CalendarMonth] = []
        var current = cal.startOfMonth(for: earliest)
        let end = cal.startOfMonth(for: latest)

        while current <= end {
            let title = current.formatted(.dateTime.month(.wide).year())

            guard let range = cal.range(of: .day, in: .month, for: current) else {
                guard let next = cal.date(byAdding: .month, value: 1, to: current) else { break }
                current = next
                continue
            }

            let rawWeekday = cal.component(.weekday, from: current)
            let offset = (rawWeekday + 5) % 7 // Mon=0 … Sun=6

            var grid: [DayInfo?] = Array(repeating: nil, count: 42)
            for day in range {
                if let date = cal.date(byAdding: .day, value: day - 1, to: current) {
                    let startOfDay = cal.startOfDay(for: date)
                    grid[offset + day - 1] = DayInfo(
                        id: startOfDay,
                        dayNumber: day,
                        isToday: startOfDay == today,
                        isEnabled: startOfDay >= enabledStart && startOfDay <= enabledEnd
                    )
                }
            }

            // Trim trailing empty rows — most months need 5 rows, not 6.
            while grid.count > 7 && grid.suffix(7).allSatisfy({ $0 == nil }) {
                grid.removeLast(7)
            }

            // Convert flat grid into WeekRows with stable IDs.
            let weeks = stride(from: 0, to: grid.count, by: 7).enumerated().map { weekIdx, startIdx in
                let slots = (startIdx..<min(startIdx + 7, grid.count)).map { i in
                    DaySlot(id: i, info: grid[i])
                }
                return WeekRow(id: weekIdx, slots: slots)
            }

            result.append(CalendarMonth(id: current, title: title, weeks: weeks))

            guard let next = cal.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }

        return result
    }

    private var orderedWeekdaySymbols: [String] {
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        return Array(symbols[1...]) + [symbols[0]]
    }
}

// MARK: - Day Cell View (Equatable — only redraws when inputs change)

private struct DayCellView: View, Equatable {
    let slot: DaySlot
    let isSelected: Bool
    let photoCount: Int
    let thumbnailIDs: [String]
    @Binding var selectedDate: Date

    static func == (lhs: DayCellView, rhs: DayCellView) -> Bool {
        lhs.slot == rhs.slot &&
        lhs.isSelected == rhs.isSelected &&
        lhs.photoCount == rhs.photoCount &&
        lhs.thumbnailIDs == rhs.thumbnailIDs
    }

    var body: some View {
        if let day = slot.info {
            Button {
                selectedDate = day.id
            } label: {
                VStack(spacing: 2) {
                    Text("\(day.dayNumber)")
                        .font(.body)
                        .fontWeight(day.isToday ? .bold : .regular)
                        .foregroundStyle({
                            guard day.isEnabled else { return AnyShapeStyle(Color.gray.opacity(0.3)) }
                            if isSelected { return AnyShapeStyle(Color.white) }
                            if day.isToday { return AnyShapeStyle(.tint) }
                            return AnyShapeStyle(.primary)
                        }())
                        .frame(width: 32, height: 32)
                        .background {
                            if isSelected {
                                Circle().fill(.tint)
                            } else if day.isToday {
                                Circle().strokeBorder(.tint, lineWidth: 1)
                            }
                        }
                        .frame(maxWidth: .infinity)

                    if thumbnailIDs.isEmpty {
                        Color.clear.frame(height: 44)
                    } else {
                        CalendarMosaicView(assetIdentifiers: thumbnailIDs, totalCount: photoCount)
                    }
                }
            }
            .disabled(!day.isEnabled)
            .id(day.id)
        } else {
            Color.clear.frame(minHeight: 78)
        }
    }
}

// MARK: - Mosaic View (Equatable, no GeometryReader)

private struct CalendarMosaicView: View, Equatable {
    let assetIdentifiers: [String]
    let totalCount: Int
    private static let mosaicHeight: CGFloat = 44

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.secondary.opacity(0.12)

            mosaic()

            if totalCount > 4 {
                Text("+\(totalCount - 4)")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.6), in: Capsule())
                    .padding(2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .frame(height: Self.mosaicHeight)
    }

    @ViewBuilder
    private func mosaic() -> some View {
        let gap: CGFloat = 1

        switch assetIdentifiers.count {
        case 1:
            thumb(assetIdentifiers[0])
        case 2:
            HStack(spacing: gap) {
                thumb(assetIdentifiers[0])
                thumb(assetIdentifiers[1])
            }
        case 3:
            HStack(spacing: gap) {
                thumb(assetIdentifiers[0])
                VStack(spacing: gap) {
                    thumb(assetIdentifiers[1])
                    thumb(assetIdentifiers[2])
                }
            }
        default:
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    thumb(assetIdentifiers[0])
                    thumb(assetIdentifiers[1])
                }
                HStack(spacing: gap) {
                    thumb(assetIdentifiers[2])
                    thumb(assetIdentifiers[3])
                }
            }
        }
    }

    private func thumb(_ id: String) -> some View {
        ThumbnailImage(id: id)
    }
}

// MARK: - Thumbnail Image

private struct ThumbnailImage: View {
    let id: String
    @State private var image: UIImage?

    var body: some View {
        Color.secondary.opacity(0.12)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .clipped()
                }
            }
            .clipped()
            .task(id: id) {
                let loaded = await PhotoLibraryService.shared.loadThumbnail(for: id)
                if !Task.isCancelled {
                    image = loaded
                }
            }
    }
}

// MARK: - Calendar Helpers

extension Calendar {
    nonisolated func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
