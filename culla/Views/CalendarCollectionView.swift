import UIKit
import SwiftUI

// MARK: - UICollectionView Bridge

struct CalendarCollectionView: UIViewRepresentable {
    let viewData: CalendarViewData
    @Binding var selectedDate: Date
    let calendar: Calendar
    let monochrome: Bool

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
        context.coordinator.update(viewData: viewData, selectedDate: selectedDate, monochrome: monochrome)
    }

    private func makeWeekdayHeader() -> UIStackView {
        // Rotated so the first column matches the grid's first weekday.
        let calendar = Calendar.current
        let symbols = calendar.shortStandaloneWeekdaySymbols
        let first = calendar.firstWeekday - 1
        let ordered = Array(symbols[first...]) + Array(symbols[..<first])

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
        private var currentMonochrome = false

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

        func update(viewData: CalendarViewData, selectedDate: Date, monochrome: Bool) {
            let monochromeChanged = monochrome != currentMonochrome
            currentMonochrome = monochrome

            let isFirstLoad = (currentViewData == nil)
            currentViewData = viewData

            if isFirstLoad {
                currentSelectedDate = selectedDate
                lastAppliedSelectedDate = selectedDate
                collectionView?.alpha = 0
                collectionView?.reloadData()
                scrollWhenReady(for: selectedDate)
                return
            }

            if monochromeChanged {
                collectionView?.reloadItems(at: collectionView?.indexPathsForVisibleItems ?? [])
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

        private func scrollWhenReady(for date: Date) {
            guard !hasScrolledToInitial else { return }
            guard let cv = collectionView, cv.bounds.height > 0 else {
                DispatchQueue.main.async { [weak self] in self?.scrollWhenReady(for: date) }
                return
            }
            hasScrolledToInitial = true
            scrollToMonth(for: date, animated: false)
            UIView.animate(withDuration: 0.25, delay: 0, options: .curveEaseOut) {
                cv.alpha = 1
            }
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
            cell.configure(day: day, isSelected: isSelected, photoCount: photoCount, thumbnailIDs: thumbnailIDs, monochrome: currentMonochrome)
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
