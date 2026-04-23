import Photos
import UIKit
import SwiftUI

// MARK: - Pre-computed Data Models

struct DayInfo: Identifiable, Equatable {
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

    var body: some View {
        Group {
            if let viewData {
                CalendarCollectionView(
                    viewData: viewData,
                    selectedDate: $selectedDate,
                    calendar: calendar
                )
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

            service.startCachingCalendarThumbnails(data.thumbnailIDs.values.flatMap { $0 })

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

            let rawWeekday = cal.component(.weekday, from: current)
            let offset = (rawWeekday + 5) % 7

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

// MARK: - UICollectionView Bridge

private struct CalendarCollectionView: UIViewRepresentable {
    let viewData: CalendarViewData
    @Binding var selectedDate: Date
    let calendar: Calendar

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedDate: $selectedDate, calendar: calendar)
    }

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .clear

        let header = makeWeekdayHeader()
        container.addSubview(header)

        let layout = Self.makeLayout()
        let cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = .clear
        cv.dataSource = context.coordinator
        cv.delegate = context.coordinator
        container.addSubview(cv)

        header.translatesAutoresizingMaskIntoConstraints = false
        cv.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
            header.heightAnchor.constraint(equalToConstant: 28),
            cv.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            cv.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            cv.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            cv.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        context.coordinator.setup(collectionView: cv)
        return container
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.update(viewData: viewData, selectedDate: selectedDate)
    }

    private func makeWeekdayHeader() -> UIStackView {
        let symbols = Calendar.current.shortStandaloneWeekdaySymbols
        let ordered = Array(symbols[1...]) + [symbols[0]]

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.distribution = .fillEqually

        for symbol in ordered {
            let label = UILabel()
            label.text = symbol.uppercased()
            label.font = .systemFont(ofSize: 11, weight: .medium)
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            stack.addArrangedSubview(label)
        }

        return stack
    }

    private static func makeLayout() -> UICollectionViewCompositionalLayout {
        UICollectionViewCompositionalLayout { _, _ in
            let itemSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0 / 7.0),
                heightDimension: .absolute(78)
            )
            let item = NSCollectionLayoutItem(layoutSize: itemSize)

            let groupSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(78)
            )
            let group = NSCollectionLayoutGroup.horizontal(
                layoutSize: groupSize,
                repeatingSubitem: item,
                count: 7
            )
            group.interItemSpacing = .fixed(0)

            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 4
            section.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 16, bottom: 16, trailing: 16)

            let headerSize = NSCollectionLayoutSize(
                widthDimension: .fractionalWidth(1.0),
                heightDimension: .absolute(44)
            )
            let sectionHeader = NSCollectionLayoutBoundarySupplementaryItem(
                layoutSize: headerSize,
                elementKind: UICollectionView.elementKindSectionHeader,
                alignment: .top
            )
            section.boundarySupplementaryItems = [sectionHeader]

            return section
        }
    }
}

// MARK: - Coordinator

extension CalendarCollectionView {

    final class Coordinator: NSObject, UICollectionViewDataSource, UICollectionViewDelegate {
        private let selectedDate: Binding<Date>
        private let calendar: Calendar
        private weak var collectionView: UICollectionView?
        private var currentViewData: CalendarViewData?
        private var currentSelectedDate: Date
        private var lastAppliedSelectedDate: Date?
        private var hasScrolledToInitial = false

        init(selectedDate: Binding<Date>, calendar: Calendar) {
            self.selectedDate = selectedDate
            self.calendar = calendar
            self.currentSelectedDate = selectedDate.wrappedValue
        }

        func setup(collectionView: UICollectionView) {
            self.collectionView = collectionView
            collectionView.register(CalendarDayCell.self, forCellWithReuseIdentifier: "day")
            collectionView.register(
                CalendarHeaderView.self,
                forSupplementaryViewOfKind: UICollectionView.elementKindSectionHeader,
                withReuseIdentifier: "header"
            )
        }

        func update(viewData: CalendarViewData, selectedDate: Date) {
            let isFirstLoad = (currentViewData == nil)
            currentViewData = viewData

            if isFirstLoad {
                currentSelectedDate = selectedDate
                lastAppliedSelectedDate = selectedDate
                collectionView?.reloadData()
                let target = selectedDate
                DispatchQueue.main.async { [weak self] in
                    guard let self, !self.hasScrolledToInitial else { return }
                    self.hasScrolledToInitial = true
                    self.scrollToMonth(for: target, animated: false)
                }
                return
            }

            if lastAppliedSelectedDate != selectedDate {
                let old = lastAppliedSelectedDate ?? selectedDate
                currentSelectedDate = selectedDate
                lastAppliedSelectedDate = selectedDate
                reloadSelection(from: old, to: selectedDate, in: viewData)
            }
        }

        private func reloadSelection(from oldDate: Date, to newDate: Date, in viewData: CalendarViewData) {
            var paths: [IndexPath] = []
            if let p = indexPath(for: oldDate, in: viewData), isValidIndexPath(p, in: viewData) { paths.append(p) }
            if let p = indexPath(for: newDate, in: viewData), isValidIndexPath(p, in: viewData) { paths.append(p) }
            guard !paths.isEmpty else { return }
            collectionView?.reloadItems(at: paths)
        }

        private func isValidIndexPath(_ indexPath: IndexPath, in viewData: CalendarViewData) -> Bool {
            guard indexPath.section < viewData.months.count else { return false }
            return indexPath.item < viewData.months[indexPath.section].days.count
        }

        private func indexPath(for date: Date, in viewData: CalendarViewData) -> IndexPath? {
            let day = calendar.startOfDay(for: date)
            let monthID = calendar.startOfMonth(for: date)
            guard let sectionIndex = viewData.months.firstIndex(where: { $0.id == monthID }),
                  let slotIndex = viewData.months[sectionIndex].days.firstIndex(where: { $0?.id == day })
            else { return nil }
            return IndexPath(item: slotIndex, section: sectionIndex)
        }

        private func scrollToMonth(for date: Date, animated: Bool) {
            let monthID = calendar.startOfMonth(for: date)
            guard let cv = collectionView,
                  let sectionIndex = currentViewData?.months.firstIndex(where: { $0.id == monthID })
            else { return }

            cv.layoutIfNeeded()
            let headerPath = IndexPath(item: 0, section: sectionIndex)
            if let attrs = cv.layoutAttributesForSupplementaryElement(
                ofKind: UICollectionView.elementKindSectionHeader,
                at: headerPath
            ) {
                let targetY = max(0, attrs.frame.minY - cv.adjustedContentInset.top)
                cv.setContentOffset(CGPoint(x: 0, y: targetY), animated: animated)
            }
        }

        // MARK: UICollectionViewDataSource

        func numberOfSections(in collectionView: UICollectionView) -> Int {
            currentViewData?.months.count ?? 0
        }

        func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
            guard let vd = currentViewData, section < vd.months.count else { return 0 }
            return vd.months[section].days.count
        }

        func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
            guard let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "day", for: indexPath) as? CalendarDayCell,
                  let vd = currentViewData,
                  indexPath.section < vd.months.count,
                  indexPath.item < vd.months[indexPath.section].days.count else {
                return UICollectionViewCell()
            }
            let month = vd.months[indexPath.section]
            let day: DayInfo? = month.days[indexPath.item]
            let isSelected = day?.id == calendar.startOfDay(for: currentSelectedDate)
            let photoCount = day.flatMap { vd.photoCounts[$0.id] } ?? 0
            let thumbnailIDs = Array((day.flatMap { vd.thumbnailIDs[$0.id] } ?? []).prefix(4))
            cell.configure(day: day, isSelected: isSelected, photoCount: photoCount, thumbnailIDs: thumbnailIDs)
            return cell
        }

        func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
            guard let header = collectionView.dequeueReusableSupplementaryView(
                ofKind: kind,
                withReuseIdentifier: "header",
                for: indexPath
            ) as? CalendarHeaderView,
                  let vd = currentViewData,
                  indexPath.section < vd.months.count
            else {
                return UICollectionReusableView()
            }
            let title = vd.months[indexPath.section].title
            header.configure(title: title)
            return header
        }

        // MARK: UICollectionViewDelegate

        func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
            collectionView.deselectItem(at: indexPath, animated: false)
            guard let vd = currentViewData,
                  indexPath.section < vd.months.count else { return }
            let month = vd.months[indexPath.section]
            guard indexPath.item < month.days.count,
                  let day = month.days[indexPath.item],
                  day.isEnabled else { return }
            selectedDate.wrappedValue = day.id
        }
    }
}

// MARK: - Day Cell

private final class CalendarDayCell: UICollectionViewCell {
    private let circleView = UIView()
    private let todayRingView = UIView()
    private let numberLabel = UILabel()
    private let mosaicView = MosaicView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        circleView.layer.cornerRadius = 16
        circleView.clipsToBounds = true
        contentView.addSubview(circleView)

        todayRingView.layer.cornerRadius = 16
        todayRingView.layer.borderWidth = 1
        todayRingView.backgroundColor = .clear
        contentView.addSubview(todayRingView)

        numberLabel.textAlignment = .center
        contentView.addSubview(numberLabel)

        contentView.addSubview(mosaicView)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layoutSubviews() {
        super.layoutSubviews()
        let w = contentView.bounds.width
        let circleSize: CGFloat = 32
        let cx = (w - circleSize) / 2
        circleView.frame = CGRect(x: cx, y: 0, width: circleSize, height: circleSize)
        todayRingView.frame = CGRect(x: cx, y: 0, width: circleSize, height: circleSize)
        numberLabel.frame = CGRect(x: 0, y: 0, width: w, height: 32)
        mosaicView.frame = CGRect(x: 0, y: 34, width: w, height: 44)
    }

    func configure(day: DayInfo?, isSelected: Bool, photoCount: Int, thumbnailIDs: [String]) {
        mosaicView.reset()

        guard let day else {
            contentView.alpha = 0
            return
        }
        contentView.alpha = 1

        numberLabel.text = "\(day.dayNumber)"
        numberLabel.font = day.isToday
            ? .boldSystemFont(ofSize: 17)
            : .systemFont(ofSize: 17)

        if !day.isEnabled {
            numberLabel.textColor = UIColor.gray.withAlphaComponent(0.3)
        } else if isSelected {
            numberLabel.textColor = .white
        } else if day.isToday {
            numberLabel.textColor = .tintColor
        } else {
            numberLabel.textColor = .label
        }

        circleView.backgroundColor = isSelected ? .tintColor : .clear
        todayRingView.isHidden = !day.isToday || isSelected
        todayRingView.layer.borderColor = UIColor.tintColor.cgColor

        if !thumbnailIDs.isEmpty {
            mosaicView.configure(thumbnailIDs: thumbnailIDs, photoCount: photoCount)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        mosaicView.reset()
        contentView.alpha = 1
    }
}

// MARK: - Month Header

private final class CalendarHeaderView: UICollectionReusableView {
    private let titleLabel = UILabel()

    override init(frame: CGRect) {
        super.init(frame: frame)
        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        addSubview(titleLabel)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func configure(title: String) {
        titleLabel.text = title
    }
}

// MARK: - Mosaic View

private final class MosaicView: UIView {
    private var imageViews: [UIImageView] = []
    private var loadTasks: [Task<Void, Never>] = []
    private let overflowLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 7, weight: .bold)
        l.textColor = .white
        l.textAlignment = .center
        l.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        l.layer.cornerRadius = 6
        l.clipsToBounds = true
        l.isHidden = true
        return l
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        layer.cornerRadius = 4
        clipsToBounds = true
        isHidden = true
        addSubview(overflowLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func reset() {
        loadTasks.forEach { $0.cancel() }
        loadTasks = []
        imageViews.forEach { $0.removeFromSuperview() }
        imageViews = []
        overflowLabel.isHidden = true
        isHidden = true
        backgroundColor = .clear
    }

    func configure(thumbnailIDs: [String], photoCount: Int) {
        let count = min(thumbnailIDs.count, 4)
        guard count > 0 else { return }

        isHidden = false
        backgroundColor = UIColor.secondarySystemFill

        for _ in 0..<count {
            let iv = UIImageView()
            iv.contentMode = .scaleAspectFill
            iv.clipsToBounds = true
            iv.backgroundColor = UIColor.secondarySystemFill
            insertSubview(iv, belowSubview: overflowLabel)
            imageViews.append(iv)
        }

        if photoCount > 4 {
            overflowLabel.text = "+\(photoCount - 4)"
            overflowLabel.isHidden = false
        }

        setNeedsLayout()

        let service = PhotoLibraryService.shared
        for (i, assetID) in thumbnailIDs.prefix(4).enumerated() {
            let task = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                let image = await service.loadThumbnail(for: assetID)
                guard !Task.isCancelled, i < self.imageViews.count else { return }
                self.imageViews[i].image = image
            }
            loadTasks.append(task)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !imageViews.isEmpty else { return }
        let w = bounds.width
        let h = bounds.height
        let gap: CGFloat = 1

        switch imageViews.count {
        case 1:
            imageViews[0].frame = bounds
        case 2:
            let hw = (w - gap) / 2
            imageViews[0].frame = CGRect(x: 0, y: 0, width: hw, height: h)
            imageViews[1].frame = CGRect(x: hw + gap, y: 0, width: w - hw - gap, height: h)
        case 3:
            let hw = (w - gap) / 2
            let hh = (h - gap) / 2
            imageViews[0].frame = CGRect(x: 0, y: 0, width: hw, height: h)
            imageViews[1].frame = CGRect(x: hw + gap, y: 0, width: w - hw - gap, height: hh)
            imageViews[2].frame = CGRect(x: hw + gap, y: hh + gap, width: w - hw - gap, height: h - hh - gap)
        default:
            let hw = (w - gap) / 2
            let hh = (h - gap) / 2
            imageViews[0].frame = CGRect(x: 0, y: 0, width: hw, height: hh)
            imageViews[1].frame = CGRect(x: hw + gap, y: 0, width: w - hw - gap, height: hh)
            imageViews[2].frame = CGRect(x: 0, y: hh + gap, width: hw, height: h - hh - gap)
            imageViews[3].frame = CGRect(x: hw + gap, y: hh + gap, width: w - hw - gap, height: h - hh - gap)
        }

        let badgeSize = CGSize(width: 26, height: 14)
        overflowLabel.frame = CGRect(
            x: w - badgeSize.width - 2,
            y: h - badgeSize.height - 2,
            width: badgeSize.width,
            height: badgeSize.height
        )
    }
}

// MARK: - Calendar Extension

extension Calendar {
    nonisolated func startOfMonth(for date: Date) -> Date {
        let components = dateComponents([.year, .month], from: date)
        return self.date(from: components) ?? date
    }
}
