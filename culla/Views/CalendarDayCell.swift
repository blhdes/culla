import UIKit

// MARK: - Day Cell

final class CalendarDayCell: UICollectionViewCell {
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

    func configure(day: DayInfo?, isSelected: Bool, photoCount: Int, thumbnailIDs: [String], monochrome: Bool) {
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
            mosaicView.configure(thumbnailIDs: thumbnailIDs, photoCount: photoCount, monochrome: monochrome)
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        mosaicView.reset()
        contentView.alpha = 1
    }
}

// MARK: - Month Header

final class CalendarHeaderView: UICollectionReusableView {
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

    func configure(thumbnailIDs: [String], photoCount: Int, monochrome: Bool) {
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

        let thumbnails = CalendarThumbnailCache.shared
        for (i, assetID) in thumbnailIDs.prefix(4).enumerated() {
            let task = Task { @MainActor [weak self] in
                guard let self, !Task.isCancelled else { return }
                var image = await thumbnails.image(for: assetID)
                if monochrome, let img = image { image = toGrayscale(img) }
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

// MARK: - Grayscale

private func toGrayscale(_ image: UIImage) -> UIImage {
    guard let cgImage = image.cgImage else { return image }
    let w = cgImage.width, h = cgImage.height
    guard let ctx = CGContext(
        data: nil, width: w, height: h,
        bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { return image }
    ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
    guard let result = ctx.makeImage() else { return image }
    return UIImage(cgImage: result, scale: image.scale, orientation: image.imageOrientation)
}
