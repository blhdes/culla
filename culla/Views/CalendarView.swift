import SwiftUI
import UIKit

// MARK: - Pre-computed Data Models

/// One calendar day's static info — computed once, never recalculated during render.
struct DayInfo: Identifiable {
    let id: Date          // startOfDay — used as dictionary key into photo data
    let dayNumber: Int    // 1–31
    let isToday: Bool
    let isEnabled: Bool
}

/// One month's worth of pre-computed grid data.
struct CalendarMonth: Identifiable {
    let id: Date          // first-of-month — used as scroll anchor
    let title: String     // "April 2024"
    let days: [DayInfo?]  // 35–42 slots (trailing empty rows trimmed)

    /// Days split into week rows of 7 for flat LazyVStack rendering.
    var weeks: [[DayInfo?]] {
        stride(from: 0, to: days.count, by: 7).map { i in
            Array(days[i..<min(i + 7, days.count)])
        }
    }
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

                                ForEach(Array(month.weeks.enumerated()), id: \.offset) { weekIdx, week in
                                    LazyVGrid(columns: columns, spacing: 4) {
                                        ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                                            dayCell(day, selectedDay: selectedDay, viewData: viewData)
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

            let data = await Task.detached(priority: .userInitiated) {
                service.calendarData(from: e, to: l, inAlbum: albumID)
            }.value

            // Pre-warm the PHCachingImageManager for every thumbnail at once.
            let allIDs = data.thumbnailIDs.values.flatMap { $0 }
            PhotoLibraryService.shared.startCachingCalendarThumbnails(allIDs)

            // Build pre-computed months and assign everything in one state mutation.
            let months = buildMonths(earliest: e, latest: l)
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

    // MARK: - Day Cell

    @ViewBuilder
    private func dayCell(_ day: DayInfo?, selectedDay: Date, viewData: CalendarViewData) -> some View {
        if let day {
            let isSelected = day.id == selectedDay
            let count = viewData.photoCounts[day.id] ?? 0
            let ids = viewData.thumbnailIDs[day.id] ?? []

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

                    if ids.isEmpty {
                        Color.clear.frame(height: 44)
                    } else {
                        CalendarMosaicView(assetIdentifiers: ids, totalCount: count)
                    }
                }
            }
            .disabled(!day.isEnabled)
            .id(day.id)
        } else {
            Color.clear.frame(minHeight: 78)
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

    /// Builds all month/day data once. Called from .task, never during render.
    private func buildMonths(earliest: Date, latest: Date) -> [CalendarMonth] {
        let cal = calendar
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

            result.append(CalendarMonth(id: current, title: title, days: grid))

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

// MARK: - Mosaic View

private struct CalendarMosaicView: View {
    let assetIdentifiers: [String]
    let totalCount: Int
    private static let mosaicHeight: CGFloat = 44

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomTrailing) {
                Color.secondary.opacity(0.12)

                mosaic(width: geo.size.width)

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
        }
        .frame(height: Self.mosaicHeight)
    }

    @ViewBuilder
    private func mosaic(width w: CGFloat) -> some View {
        let h = Self.mosaicHeight
        let gap: CGFloat = 1
        let hw = (w - gap) / 2
        let hh = (h - gap) / 2

        switch assetIdentifiers.count {
        case 1:
            thumb(assetIdentifiers[0], w: w, h: h)
        case 2:
            HStack(spacing: gap) {
                thumb(assetIdentifiers[0], w: hw, h: h)
                thumb(assetIdentifiers[1], w: hw, h: h)
            }
            .frame(width: w, height: h)
        case 3:
            HStack(spacing: gap) {
                thumb(assetIdentifiers[0], w: hw, h: h)
                VStack(spacing: gap) {
                    thumb(assetIdentifiers[1], w: hw, h: hh)
                    thumb(assetIdentifiers[2], w: hw, h: hh)
                }
                .frame(width: hw, height: h)
            }
            .frame(width: w, height: h)
        default: // 4
            VStack(spacing: gap) {
                HStack(spacing: gap) {
                    thumb(assetIdentifiers[0], w: hw, h: hh)
                    thumb(assetIdentifiers[1], w: hw, h: hh)
                }
                .frame(width: w, height: hh)
                HStack(spacing: gap) {
                    thumb(assetIdentifiers[2], w: hw, h: hh)
                    thumb(assetIdentifiers[3], w: hw, h: hh)
                }
                .frame(width: w, height: hh)
            }
            .frame(width: w, height: h)
        }
    }

    private func thumb(_ id: String, w: CGFloat, h: CGFloat) -> some View {
        ThumbnailImage(id: id)
            .frame(width: w, height: h)
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
                        .transition(.opacity)
                }
            }
            .clipped()
            .task(id: id) {
                let loaded = await PhotoLibraryService.shared.loadThumbnail(for: id)
                if !Task.isCancelled {
                    withAnimation(.easeIn(duration: 0.15)) {
                        image = loaded
                    }
                }
            }
    }
}

// MARK: - Calendar Helpers

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
