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
                proxy.scrollTo(calendar.startOfMonth(for: selectedDate), anchor: .top)
            }
        }
        .task {
            let albumID = albumIdentifier
            let data = await Task.detached(priority: .userInitiated) {
                PhotoLibraryService.shared.calendarData(from: earliest, to: latest, inAlbum: albumID)
            }.value
            photoCounts = data.counts
            thumbnailIDs = data.thumbnailIDs
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
                        .foregroundStyle(
                            !isEnabled ? Color.gray.opacity(0.3) :
                            isSelected ? Color.white :
                            isToday ? Color.accentColor :
                            Color.primary
                        )
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background {
                            if isSelected {
                                Circle().fill(Color.accentColor)
                            } else if isToday {
                                Circle().strokeBorder(Color.accentColor, lineWidth: 1)
                            }
                        }

                    if ids.isEmpty {
                        Spacer().frame(height: 36)
                    } else {
                        CalendarMosaicView(assetIdentifiers: ids, totalCount: count)
                    }
                }
            }
            .disabled(!isEnabled)
        } else {
            Color.clear.frame(minHeight: 68)
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

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            mosaicLayout
                .frame(maxWidth: .infinity)
                .frame(height: 34)
                .clipShape(RoundedRectangle(cornerRadius: 4))

            if totalCount > 4 {
                Text("\(totalCount)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 1)
                    .background(.black.opacity(0.55), in: Capsule())
                    .padding(2)
            }
        }
    }

    @ViewBuilder
    private var mosaicLayout: some View {
        switch assetIdentifiers.count {
        case 1:
            ThumbnailImage(id: assetIdentifiers[0])
        case 2:
            HStack(spacing: 1) {
                ThumbnailImage(id: assetIdentifiers[0])
                ThumbnailImage(id: assetIdentifiers[1])
            }
        case 3:
            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    ThumbnailImage(id: assetIdentifiers[0])
                    ThumbnailImage(id: assetIdentifiers[1])
                }
                ThumbnailImage(id: assetIdentifiers[2])
            }
        default: // 4
            VStack(spacing: 1) {
                HStack(spacing: 1) {
                    ThumbnailImage(id: assetIdentifiers[0])
                    ThumbnailImage(id: assetIdentifiers[1])
                }
                HStack(spacing: 1) {
                    ThumbnailImage(id: assetIdentifiers[2])
                    ThumbnailImage(id: assetIdentifiers[3])
                }
            }
        }
    }
}

// MARK: - Thumbnail Image

private struct ThumbnailImage: View {
    let id: String
    @State private var image: UIImage?

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task {
            image = await PhotoLibraryService.shared.loadImage(
                for: id,
                targetSize: CGSize(width: 80, height: 80)
            )
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
