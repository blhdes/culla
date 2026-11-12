import SwiftUI

// MARK: - Pre-computed Data Models

/// Plain data built on a background thread (see `buildMonths`), so it opts out
/// of the app's default main-thread isolation.
nonisolated struct DayInfo: Identifiable, Equatable {
    let id: Date
    let dayNumber: Int
    let isToday: Bool
    let isEnabled: Bool
}

struct CalendarMonth: Identifiable {
    let id: Date
    let title: String
    let days: [DayInfo?]
    let weeks: [[DayInfo?]]

    nonisolated init(id: Date, title: String, days: [DayInfo?]) {
        self.id = id
        self.title = title
        self.days = days
        self.weeks = stride(from: 0, to: days.count, by: 7).map { i in
            Array(days[i..<min(i + 7, days.count)])
        }
    }
}

struct CalendarViewData {
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

    @AppStorage("monochromeBackground") private var monochrome = false
    @State private var viewData: CalendarViewData?
    private let calendar = Calendar.current

    var body: some View {
        Group {
            if let viewData {
                CalendarCollectionView(
                    viewData: viewData,
                    selectedDate: $selectedDate,
                    calendar: calendar,
                    monochrome: monochrome
                )
            } else {
                ProgressView()
            }
        }
        .onDisappear { viewData = nil }
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

            viewData = CalendarViewData(
                months: months,
                photoCounts: data.counts,
                thumbnailIDs: data.thumbnailIDs
            )
        }
    }

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

            // Empty cells before day 1. The week starts on the user's region's
            // first weekday (Monday in Spain, Sunday in the US).
            let rawWeekday = cal.component(.weekday, from: current)
            let offset = (rawWeekday - cal.firstWeekday + 7) % 7

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

            while grid.count > 7 && grid.suffix(7).allSatisfy({ $0 == nil }) {
                grid.removeLast(7)
            }

            result.append(CalendarMonth(id: current, title: title, days: grid))

            guard let next = cal.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }

        return result
    }
}

// MARK: - Calendar Extension

extension Calendar {
    nonisolated func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
