import SwiftUI
import UIKit

struct CalendarView: View {
    @Binding var selectedDate: Date
    var earliest: Date = .distantPast
    var latest: Date = .distantFuture
    var albumIdentifier: String? = nil

    @State private var photoCounts: [Date: Int] = [:]
    @State private var thumbnailIDs: [Date: [String]] = [:]

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 24) {
                    weekdayHeader
                        .padding(.horizontal)

                    ForEach(months, id: \.self) { month in
                        monthSection(month)
                            .id(month)
                    }
                }
                .padding(.vertical)
            }
            .onAppear {
                let target = calendar.startOfMonth(for: selectedDate)
                DispatchQueue.main.async {
                    proxy.scrollTo(target, anchor: .top)
                }
            }
        }
        .task {
            let albumID = albumIdentifier
            let service = PhotoLibraryService.shared
            let data = await Task.detached(priority: .userInitiated) {
                service.calendarData(from: earliest, to: latest, inAlbum: albumID)
            }.value
            photoCounts = data.counts
            thumbnailIDs = data.thumbnailIDs

            // Pre-warm the PHCachingImageManager for every thumbnail at once.
            // Cells that render later hit the cache instead of fetching cold.
            let allIDs = data.thumbnailIDs.values.flatMap { $0 }
            PhotoLibraryService.shared.startCachingCalendarThumbnails(allIDs)
        }
        .onDisappear {
            PhotoLibraryService.shared.stopCachingAll()
        }
    }

    // MARK: - Month Section

    private func monthSection(_ month: Date) -> some View {
        VStack(spacing: 8) {
            Text(month.formatted(.dateTime.month(.wide).year()))
                .font(.body)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(daysInGrid(for: month).enumerated()), id: \.offset) { _, day in
                    dayCell(day)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: - Day Cell

    @ViewBuilder
    private func dayCell(_ day: Date?) -> some View {
        if let day {
            let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
            let isToday = calendar.isDateInToday(day)
            let isEnabled = day >= calendar.startOfDay(for: earliest)
                         && day <= calendar.startOfDay(for: latest)
            let dayKey = calendar.startOfDay(for: day)
            let count = photoCounts[dayKey] ?? 0
            let ids = thumbnailIDs[dayKey] ?? []

            Button {
                selectedDate = day
            } label: {
                VStack(spacing: 2) {
                    Text("\(calendar.component(.day, from: day))")
                        .font(.body)
                        .fontWeight(isToday ? .bold : .regular)
                        .foregroundStyle({
                            guard isEnabled else { return AnyShapeStyle(Color.gray.opacity(0.3)) }
                            if isSelected { return AnyShapeStyle(Color.white) }
                            if isToday    { return AnyShapeStyle(.tint) }
                            return AnyShapeStyle(.primary)
                        }())
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background {
                            if isSelected {
                                Circle().fill(.tint)
                            } else if isToday {
                                Circle().strokeBorder(.tint, lineWidth: 1)
                            }
                        }

                    if ids.isEmpty {
                        Color.clear.frame(height: 44)
                    } else {
                        CalendarMosaicView(assetIdentifiers: ids, totalCount: count)
                    }
                }
            }
            .disabled(!isEnabled)
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

    // MARK: - Grid Data

    private var months: [Date] {
        var result: [Date] = []
        var current = calendar.startOfMonth(for: earliest)
        let end = calendar.startOfMonth(for: latest)
        while current <= end {
            result.append(current)
            guard let next = calendar.date(byAdding: .month, value: 1, to: current) else { break }
            current = next
        }
        return result
    }

    private func daysInGrid(for month: Date) -> [Date?] {
        let first = calendar.startOfMonth(for: month)
        guard let range = calendar.range(of: .day, in: .month, for: first) else { return [] }

        let rawWeekday = calendar.component(.weekday, from: first)
        let offset = (rawWeekday + 5) % 7 // Mon=0 … Sun=6

        var grid: [Date?] = Array(repeating: nil, count: 42)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: first) {
                grid[offset + day - 1] = date
            }
        }
        return grid
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
                // Fills the 1pt gaps between tiles with a consistent color instead of
                // letting the screen background bleed through.
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
        // Color fills the exact proposed frame (set by .frame(width:height:) on the caller).
        // The overlay is bounded to that same frame, so scaledToFill + clipped never bleeds
        // outside the cell — fixing the thumbnail overlap issue.
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
                image = await PhotoLibraryService.shared.loadThumbnail(for: id)
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
